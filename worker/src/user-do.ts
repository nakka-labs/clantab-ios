import { DurableObject } from "cloudflare:workers";
import { USER_META_KEYS, USER_SCHEMA, USER_SCHEMA_VERSION } from "./lib/schema.ts";

type MembershipRow = { group_id: string; member_id: string; display_name: string; hidden: number };

/** One entry in a user's group index. */
export interface Membership {
  groupId: string;
  memberId: string;
  displayName: string;
  /** Mirrors `GroupSummary.hidden` — a private 1:1 tab (`CHECKLIST.md`
   * "Friends/contacts list... + private 1:1 tabs"), cached here so the client
   * can omit it from the visible groups list / dashboard totals without a
   * per-group round-trip. */
  hidden: boolean;
}

/**
 * One per signed-in identity — Apple or Google — addressed by
 * `idFromName("<provider>:<sub>")` (`MANDATORY_LOGIN_PLAN.md` Part 2). Holds a
 * thin index — "which groups, as which member" — and nothing else
 * (`ACCOUNTS_DESIGN.md` §1). `GroupDO` is authoritative for the membership↔identity
 * link; this DO is a self-healing cache the Worker updates *after* the `GroupDO`
 * write (`ACCOUNTS_DESIGN.md` §2). A group's *contents* are never stored here —
 * they come only from `GET /api/groups/:groupId`.
 */
export class UserDO extends DurableObject {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    ctx.blockConcurrencyWhile(async () => {
      this.sql.exec(USER_SCHEMA);
      this.migrate();
    });
  }

  /** In-place migrations, mirroring `GroupDO.migrate()` (`DESIGN.md` §10).
   * Runs on every construction, before any request is served. An identity
   * that hasn't `ensureExists`-ed yet has no `schema_version` row and is left
   * alone — `USER_SCHEMA` already builds the current shape. */
  private migrate(): void {
    let current = this.meta(USER_META_KEYS.schemaVersion);
    if (current === null) return;

    if (current === "1") {
      // v2: memberships.hidden (private 1:1 tabs, CHECKLIST.md). Every
      // pre-existing row defaults to 0 — the feature didn't exist before.
      this.sql.exec("ALTER TABLE memberships ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0");
      this.setMeta(USER_META_KEYS.schemaVersion, "2");
      current = "2";
    }
  }

  /** Create the identity record on first sign-in. `identity` is the composite
   * `"<provider>:<sub>"` string this DO was addressed by. Idempotent — safe to
   * call on every sign-in. Returns whether this call created it. */
  async ensureExists(identity: string): Promise<{ created: boolean }> {
    if (this.meta(USER_META_KEYS.identity) !== null) return { created: false };
    const now = Date.now();
    this.setMeta(USER_META_KEYS.identity, identity);
    this.setMeta(USER_META_KEYS.createdAt, String(now));
    this.setMeta(USER_META_KEYS.schemaVersion, USER_SCHEMA_VERSION);
    return { created: true };
  }

  /** Whether this identity has ever signed in (drives whether the Worker mints a
   * fresh session vs. treats the token as stale after account deletion). */
  async exists(): Promise<boolean> {
    return this.meta(USER_META_KEYS.identity) !== null;
  }

  /** Store the Apple refresh token from the sign-in code exchange, for
   * revocation on account deletion (`ACCOUNTS_DESIGN.md` §11). Overwrites on
   * each sign-in that provides one. */
  async setRefreshToken(token: string): Promise<void> {
    this.setMeta(USER_META_KEYS.appleRefreshToken, token);
  }

  async refreshToken(): Promise<string | null> {
    return this.meta(USER_META_KEYS.appleRefreshToken);
  }

  /** Record (or clear) that this identity has a profile photo (`CHECKLIST.md`
   * "Profile photos"). The claim path reads `hasAvatar()` to seed
   * `members.avatar_key`; the value is an epoch-ms stamp for a future "photo
   * since" display. */
  async setAvatarUploaded(uploaded: boolean): Promise<void> {
    if (uploaded) {
      this.setMeta(USER_META_KEYS.avatarUploadedAt, String(Date.now()));
    } else {
      this.sql.exec("DELETE FROM user_meta WHERE key = ?", USER_META_KEYS.avatarUploadedAt);
    }
  }

  async hasAvatar(): Promise<boolean> {
    return this.meta(USER_META_KEYS.avatarUploadedAt) !== null;
  }

  /** The identity's groups, newest-claimed first. Returns groupIds + the member
   * id within each — never group contents. */
  async listGroups(): Promise<{ groups: Membership[] }> {
    const rows = this.sql
      .exec<MembershipRow>(
        "SELECT group_id, member_id, display_name, hidden FROM memberships ORDER BY added_at DESC, rowid DESC",
      )
      .toArray();
    return {
      groups: rows.map((r) => ({
        groupId: r.group_id,
        memberId: r.member_id,
        displayName: r.display_name,
        hidden: r.hidden !== 0,
      })),
    };
  }

  /** Record a claimed membership. Idempotent per group — a repeat with the same
   * group overwrites (a claim always follows a successful `GroupDO.claim`, which
   * enforces one identity per group, so the group id is a safe key). `hidden`
   * mirrors the group's own `group_meta.hidden` at the moment of claiming —
   * `true` only for a private 1:1 tab (`CHECKLIST.md`); it doesn't change after
   * (a group's hidden-ness is set once, at creation, and never toggled). */
  async addMembership(groupId: string, memberId: string, displayName: string, hidden = false): Promise<void> {
    this.sql.exec(
      `INSERT INTO memberships (group_id, member_id, display_name, added_at, hidden)
       VALUES (?, ?, ?, ?, ?)
       ON CONFLICT(group_id) DO UPDATE SET
         member_id = excluded.member_id,
         display_name = excluded.display_name,
         hidden = excluded.hidden`,
      groupId,
      memberId,
      displayName,
      Date.now(),
      hidden ? 1 : 0,
    );
  }

  /** Drop one membership from the index (account deletion, or reconciliation). */
  async removeMembership(groupId: string): Promise<void> {
    this.sql.exec("DELETE FROM memberships WHERE group_id = ?", groupId);
  }

  /** Tear the identity down completely — a future sign-in with the same Apple ID
   * starts fresh (`ACCOUNTS_DESIGN.md` §11). */
  async deleteAll(): Promise<void> {
    this.sql.exec("DELETE FROM memberships");
    this.sql.exec("DELETE FROM user_meta");
    this.sql.exec("DELETE FROM devices");
  }

  // --- push notifications (FEATURE_BACKLOG.md "Push notifications") ------

  /** Register a device token for push (idempotent — re-registering the same
   * token, e.g. on every launch, is a safe no-op). One identity can hold
   * several tokens (multiple devices); all get notified. */
  async registerDevice(token: string, platform: string): Promise<void> {
    this.sql.exec(
      "INSERT INTO devices (token, platform, added_at) VALUES (?, ?, ?) ON CONFLICT(token) DO NOTHING",
      token,
      platform,
      Date.now(),
    );
  }

  /** Forget a device token — sign-out, or APNs reporting it dead
   * (`Unregistered`/`BadDeviceToken`). Idempotent. */
  async unregisterDevice(token: string): Promise<void> {
    this.sql.exec("DELETE FROM devices WHERE token = ?", token);
  }

  /** Every currently-registered device token for this identity, for push
   * fan-out. */
  async deviceTokens(): Promise<string[]> {
    return this.sql.exec<{ token: string }>("SELECT token FROM devices").toArray().map((r) => r.token);
  }

  // --- helpers -----------------------------------------------------------

  private meta(key: string): string | null {
    const rows = this.sql
      .exec<{ value: string }>("SELECT value FROM user_meta WHERE key = ?", key)
      .toArray();
    return rows.length > 0 ? rows[0]!.value : null;
  }

  private setMeta(key: string, value: string): void {
    this.sql.exec(
      "INSERT INTO user_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      key,
      value,
    );
  }
}
