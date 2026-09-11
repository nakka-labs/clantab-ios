// SQLite DDL for the Durable Objects (`DESIGN.md` §3). All money columns are
// INTEGER minor units — never REAL. Foreign-key REFERENCES from `DESIGN.md` are
// omitted (the DO validates every referenced id in code, per §6) but the column
// meaning is unchanged.

export const GROUP_SCHEMA = `
CREATE TABLE IF NOT EXISTS group_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS members (
  id           TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  identity_sub TEXT,
  upi_vpa      TEXT,
  -- R2 object key for the linked identity's profile photo (CHECKLIST.md
  -- "Profile photos"), denormalised here so getState can hand it to every
  -- member without exposing identity subjects. Seeded at claim; the
  -- PUT/DELETE /api/auth/avatar fan-out keeps it current across the
  -- identity's groups. NULL = guest, or a claimed member with no photo.
  avatar_key   TEXT
);

CREATE TABLE IF NOT EXISTS expenses (
  id            TEXT PRIMARY KEY,
  payer_id      TEXT NOT NULL,
  amount_minor  INTEGER NOT NULL,
  description   TEXT NOT NULL,
  expense_date  TEXT NOT NULL,
  split_type    TEXT NOT NULL CHECK (split_type IN ('equal','exact','percentage','itemized','shares')),
  created_at    INTEGER NOT NULL,
  category      TEXT,
  category_icon TEXT,
  currency      TEXT,
  deleted_at    INTEGER,
  deleted_by    TEXT,
  -- JSON array of { id, name, amountMinor, participantIds } for an 'itemized'
  -- expense (FEATURE_BACKLOG.md "Itemized expense entry"); NULL otherwise. Read
  -- and written whole with the expense, never queried into -- so a column, not
  -- its own table.
  items         TEXT,
  -- JSON array of R2 object keys (expenses/<groupId>/<expenseId>/<id>) for
  -- receipt photos (CHECKLIST.md "Photo attachment on an expense"); NULL when
  -- there are none. Written whole with the expense.
  attachments   TEXT,
  -- JSON array of { memberId, weight } for a 'shares' expense (CHECKLIST.md
  -- "Split by shares"); NULL otherwise. Written whole with the expense.
  shares        TEXT
);

CREATE TABLE IF NOT EXISTS expense_splits (
  expense_id   TEXT NOT NULL,
  member_id    TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  PRIMARY KEY (expense_id, member_id)
);

CREATE TABLE IF NOT EXISTS settlements (
  id           TEXT PRIMARY KEY,
  from_id      TEXT NOT NULL,
  to_id        TEXT NOT NULL,
  amount_minor INTEGER NOT NULL,
  settled_at   INTEGER NOT NULL,
  currency     TEXT,
  deleted_at   INTEGER,
  deleted_by   TEXT
);
`;

/**
 * `UserDO` — one per signed-in identity, addressed by
 * `idFromName("<provider>:<sub>")` (`apple:…` or `google:…`,
 * `MANDATORY_LOGIN_PLAN.md` Part 2). A thin per-identity index of "which
 * groups, as which member" (`ACCOUNTS_DESIGN.md` §1). At most one membership
 * per group per identity (PK on `group_id`).
 */
export const USER_SCHEMA = `
CREATE TABLE IF NOT EXISTS user_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memberships (
  group_id     TEXT PRIMARY KEY,
  member_id    TEXT NOT NULL,
  display_name TEXT NOT NULL,
  added_at     INTEGER NOT NULL
);

-- Registered APNs device tokens, for push notifications
-- (FEATURE_BACKLOG.md "Push notifications"). One identity can hold several
-- (phone + iPad, or a reinstall that got a new token before the old one
-- expired) -- all get notified. Re-registering the same token is a no-op
-- (PK on token); added_at isn't touched on re-registration, nothing to
-- gain from it.
CREATE TABLE IF NOT EXISTS devices (
  token    TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  added_at INTEGER NOT NULL
);
`;

export const USER_META_KEYS = {
  /** The composite `"<provider>:<sub>"` identity string this DO was created
   * for — the same value `idFromName` addressed it by. */
  identity: "identity",
  createdAt: "created_at",
  schemaVersion: "schema_version",
  /** Apple refresh token, from the sign-in `authorizationCode` exchange — used
   * to revoke on account deletion (Apple Guideline 5.1.1(v)). Only present when
   * the identity is Apple's and the `SIWA_*` config is configured — Google's
   * flow requests no offline access, so this stays unset for Google identities. */
  appleRefreshToken: "apple_refresh_token",
  /** Epoch-ms string, set when this identity uploads a profile photo and
   * deleted when they remove it (`CHECKLIST.md` "Profile photos"). Presence is
   * the "has a photo" bit the claim path reads to seed `members.avatar_key`;
   * the value itself is only for a future "photo since" display. A new
   * `user_meta` key — no `USER_SCHEMA_VERSION` bump. */
  avatarUploadedAt: "avatar_uploaded_at",
} as const;

export const USER_SCHEMA_VERSION = "1";

/**
 * `ReportsDO` — one global singleton (`idFromName("global")`), the content-
 * report log required by Apple Guideline 1.2 for any app with shared
 * user-generated content (`SHIP_PLAN.md` Track 3 §7): group names, member
 * names, and expense descriptions are all user-typed and shared between
 * whoever holds a group's link. Deliberately a singleton — unlike the
 * retired `RegistryDO` (a chokepoint on every group creation/join-code
 * lookup, real request volume), reports are rare by design, and the owner
 * needs one place to see all of them rather than polling every group's own
 * unguessable `groupId`.
 */
export const REPORTS_SCHEMA = `
CREATE TABLE IF NOT EXISTS reports (
  id           TEXT PRIMARY KEY,
  group_id     TEXT NOT NULL,
  target_type  TEXT NOT NULL CHECK (target_type IN ('group','member')),
  target_id    TEXT,
  reason       TEXT NOT NULL,
  details      TEXT,
  reported_by  TEXT,
  created_at   INTEGER NOT NULL
);
`;

/** `group_meta` keys written at creation (`DESIGN.md` §3 + §10). */
export const META_KEYS = {
  name: "name",
  currency: "currency",
  joinCode: "join_code",
  createdAt: "created_at",
  schemaVersion: "schema_version",
  /** The rotatable capability-link credential (`ACCESS_TOKEN_PLAN.md`) —
   * separate from `groupId`, which permanently identifies the DO. Written at
   * creation for every group from here on; absent on a group created before
   * this feature shipped (`requireGroup` treats "no row" as open access,
   * unchanged from before — a deliberate backward-compat choice, not a bug). */
  accessToken: "access_token",
  /** A single emoji the group picked as its visual identity (`CHECKLIST.md`
   * "Group visual identity") — shown in the groups list and the Group Home
   * header. Optional and user-set via `PATCH /api/groups/:groupId`; a new
   * key in an existing key/value table, so no `SCHEMA_VERSION` bump (same as
   * `access_token`). Absent ("no row") = the group has no emoji. */
  emoji: "emoji",
  /** ISO 8601 timestamp the group was archived at (`CHECKLIST.md` "Archive a
   * group") — a group-wide "this trip is over, hide it" flag, reversible by
   * any member. Absent ("no row") = active. A new key in the existing
   * key/value table, so no `SCHEMA_VERSION` bump (same as `emoji` /
   * `access_token`). Purely organizational — it doesn't block mutations. */
  archivedAt: "archived_at",
  /** JSON `{ weights: [{ memberId, weight }] }` — the group's saved default
   * split (`FEATURE_BACKLOG.md` "Default split config per group"), percentage
   * weights that pre-fill Add Expense. Absent = split equally. Weights are
   * positive ints summing to 100; a new key, no `SCHEMA_VERSION` bump. */
  defaultSplit: "default_split",
  /** A **read-only** capability secret, separate from `access_token`
   * (`FEATURE_BACKLOG.md` "Read-only web link for balances"): it only
   * authorizes `GET /g/:groupId/balances`, never a write. Lazily minted the
   * first time someone shares a view-only link; absent until then. A new
   * key, no `SCHEMA_VERSION` bump. */
  viewToken: "view_token",
  /** R2 object key for the group's cover image (`CHECKLIST.md` "Group cover
   * image") — always `groups/<groupId>/cover`, so its presence is the "has a
   * cover" signal. Set/cleared via `PATCH /api/groups/:groupId` with
   * `{ "coverImage": true | null }` (the client uploads the bytes to R2 via
   * `POST /api/media/presign` first). Absent = no cover. A new key, no
   * `SCHEMA_VERSION` bump (same as `emoji` / `archived_at`). */
  coverKey: "cover_key",
  /** Present ("1") only on an auto-created private 1:1 tab (`CHECKLIST.md`
   * "Friends/contacts list... + private 1:1 tabs") — a hidden, two-person
   * group created lazily between two already-connected identities, never
   * shown in the groups list / dashboard totals, reached only via the
   * Friends screen. Absent = a normal, visible group. Set once at creation
   * (`GroupDO.markHidden`), never toggled after. A new key, no
   * `SCHEMA_VERSION` bump (same as `emoji` / `archived_at`). */
  hidden: "hidden",
} as const;

/**
 * Bump when a `GroupDO` needs an in-place migration (`DESIGN.md` §10). History:
 *  - `1` → initial v1 shape.
 *  - `2` → `expenses.split_type` CHECK widened to allow `'percentage'`. SQLite
 *          can't alter a CHECK in place, so `GroupDO.migrate` rebuilds the table.
 *  - `3` → `expenses.category` + `expenses.category_icon` added (nullable).
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `4` → `expenses.currency` + `settlements.currency` added (nullable), then
 *          backfilled from the group's currency. Multi-currency ledgers.
 *  - `5` → `members.identity_sub` added (nullable). Every existing member is a
 *          placeholder (NULL); claiming links a member to an Apple identity.
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild. See `ACCOUNTS_DESIGN.md`.
 *  - `6` → `expenses.deleted_at` / `.deleted_by` and `settlements.deleted_at` /
 *          `.deleted_by` added (nullable). Delete becomes soft — a row with
 *          `deleted_at` set is excluded from balances/getState but stays in
 *          storage for "Recently Deleted" + Restore (`FEATURE_BACKLOG.md`).
 *          Plain `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `7` → `members.upi_vpa` added (nullable). User-supplied, never verified —
 *          `FEATURE_BACKLOG.md` "UPI deep link on Settle Up". Plain
 *          `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `8` → `expenses.split_type` CHECK widened again to allow `'itemized'`, and
 *          `expenses.items` (nullable JSON) added. Like v2, SQLite can't alter a
 *          CHECK in place, so `GroupDO.migrate` rebuilds the `expenses` table
 *          (now with all v7 columns + `items`). `FEATURE_BACKLOG.md` "Itemized
 *          expense entry".
 *  - `9` → `members.avatar_key` added (nullable). Denormalised profile-photo
 *          key (`CHECKLIST.md` "Profile photos"); every existing member has
 *          none. Plain `ALTER TABLE ... ADD COLUMN` — no rebuild.
 *  - `10` → `expenses.attachments` (nullable JSON array of R2 keys) added.
 *          Receipt photos (`CHECKLIST.md` "Photo attachment on an expense");
 *          every existing expense has none. Plain `ALTER TABLE ... ADD COLUMN`.
 *  - `11` → `expenses.split_type` CHECK widened again to allow `'shares'`, and
 *          `expenses.shares` (nullable JSON) added. Like v2/v8, SQLite can't
 *          alter a CHECK in place, so `expenses` is rebuilt (all v10 columns +
 *          `shares`). `CHECKLIST.md` "Split by shares".
 */
export const SCHEMA_VERSION = "11";
