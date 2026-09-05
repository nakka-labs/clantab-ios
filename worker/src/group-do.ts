import { DurableObject } from "cloudflare:workers";
import { computeBalances } from "./lib/balances.ts";
import { newAccessToken, newMemberId, newRecordId } from "./lib/ids.ts";
import { simplify } from "./lib/simplify.ts";
import { type Result, fail, ok } from "./lib/result.ts";
import { GROUP_SCHEMA, META_KEYS, SCHEMA_VERSION } from "./lib/schema.ts";
import {
  ValidationFailure,
  assertMembersExist,
  assertPositiveAmount,
  assertSplitsSum,
} from "./lib/validation.ts";
import type {
  AddExpenseRequest,
  AddSettlementRequest,
  Expense,
  GroupStateResponse,
  GroupSummary,
  Member,
  Settlement,
} from "./types.ts";

/** ISO 8601 at seconds precision — the iOS client's `.iso8601` decoder rejects
 * fractional seconds, so never emit them. */
function isoSeconds(ms: number): string {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");
}

/** `sql.exec<T>()` constrains rows to `Record<string, SqlStorageValue>`. */
type Row<T> = T & Record<string, SqlStorageValue>;

type MemberRow = Row<{
  id: string;
  display_name: string;
  identity_sub: string | null;
  upi_vpa: string | null;
}>;
type ExpenseRow = Row<{
  id: string;
  payer_id: string;
  amount_minor: number;
  description: string;
  expense_date: string;
  split_type: "equal" | "exact" | "percentage";
  category: string | null;
  category_icon: string | null;
  currency: string;
  deleted_at: number | null;
  deleted_by: string | null;
}>;
type SplitRow = Row<{
  expense_id: string;
  member_id: string;
  amount_minor: number;
}>;
type SettlementRow = Row<{
  id: string;
  from_id: string;
  to_id: string;
  amount_minor: number;
  settled_at: number;
  currency: string;
  deleted_at: number | null;
  deleted_by: string | null;
}>;

/** One other claimed member, from the caller's point of view — used only by
 * `peerSettlements` for cross-group settling. */
export interface PeerView {
  memberId: string;
  sub: string;
  displayName: string;
  edges: { currency: string; amountMinor: number; youPay: boolean }[];
}

/**
 * One group's ledger. Addressed by `idFromName(groupId)` (`DESIGN.md` §1). Every
 * request runs to completion before the next starts (`DESIGN.md` §4), so there is
 * no read-modify-write race on balances — they're recomputed on read.
 */
export class GroupDO extends DurableObject {
  private readonly sql: SqlStorage;

  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    ctx.blockConcurrencyWhile(async () => {
      this.sql.exec(GROUP_SCHEMA);
      this.migrate();
    });
  }

  /**
   * In-place schema migrations (`DESIGN.md` §10). Runs on every construction,
   * inside `blockConcurrencyWhile`, before any request is served. A group that
   * hasn't been `initGroup`-ed has no `schema_version` row and is left alone —
   * `GROUP_SCHEMA` already builds the current shape and `initGroup` stamps the
   * current `SCHEMA_VERSION`.
   */
  private migrate(): void {
    let current = this.meta(META_KEYS.schemaVersion);
    if (current === null) return;

    if (current === "1") {
      // v2: widen `expenses.split_type` to allow 'percentage'. A `CREATE TABLE
      // IF NOT EXISTS` can't change an existing table's CHECK, so rebuild it —
      // SQLite's supported path for a constraint change. `expense_splits` has no
      // real FK (see `schema.ts`), so nothing cascades.
      this.sql.exec(`
        ALTER TABLE expenses RENAME TO expenses_v1;
        CREATE TABLE expenses (
          id           TEXT PRIMARY KEY,
          payer_id     TEXT NOT NULL,
          amount_minor INTEGER NOT NULL,
          description  TEXT NOT NULL,
          expense_date TEXT NOT NULL,
          split_type   TEXT NOT NULL CHECK (split_type IN ('equal','exact','percentage')),
          created_at   INTEGER NOT NULL
        );
        INSERT INTO expenses SELECT * FROM expenses_v1;
        DROP TABLE expenses_v1;
      `);
      this.setMeta(META_KEYS.schemaVersion, "2");
      current = "2";
    }

    if (current === "2") {
      // v3: add the category columns (nullable). In-place, no rebuild.
      this.sql.exec(`
        ALTER TABLE expenses ADD COLUMN category TEXT;
        ALTER TABLE expenses ADD COLUMN category_icon TEXT;
      `);
      this.setMeta(META_KEYS.schemaVersion, "3");
      current = "3";
    }

    if (current === "3") {
      // v4: add `currency` to both tables (nullable), then backfill every
      // existing row from the group's currency — before v4 a group was
      // single-currency, so that's exactly right.
      this.sql.exec(`
        ALTER TABLE expenses ADD COLUMN currency TEXT;
        ALTER TABLE settlements ADD COLUMN currency TEXT;
      `);
      const groupCurrency = this.requireMeta(META_KEYS.currency);
      this.sql.exec("UPDATE expenses SET currency = ? WHERE currency IS NULL", groupCurrency);
      this.sql.exec("UPDATE settlements SET currency = ? WHERE currency IS NULL", groupCurrency);
      this.setMeta(META_KEYS.schemaVersion, "4");
      current = "4";
    }

    if (current === "4") {
      // v5: add `members.identity_sub` (nullable). Every existing member stays a
      // placeholder (NULL) — exactly their status today. In-place, no rebuild.
      this.sql.exec("ALTER TABLE members ADD COLUMN identity_sub TEXT");
      this.setMeta(META_KEYS.schemaVersion, "5");
      current = "5";
    }

    if (current === "5") {
      // v6: delete becomes soft. `deleted_at` / `deleted_by` on both tables
      // (nullable); every existing row is untouched (NULL = active).
      // In-place, no rebuild. See `FEATURE_BACKLOG.md` "Delete goes to trash".
      this.sql.exec(`
        ALTER TABLE expenses ADD COLUMN deleted_at INTEGER;
        ALTER TABLE expenses ADD COLUMN deleted_by TEXT;
        ALTER TABLE settlements ADD COLUMN deleted_at INTEGER;
        ALTER TABLE settlements ADD COLUMN deleted_by TEXT;
      `);
      this.setMeta(META_KEYS.schemaVersion, "6");
      current = "6";
    }

    if (current === "6") {
      // v7: add `members.upi_vpa` (nullable). Every existing member has none
      // set — `FEATURE_BACKLOG.md` "UPI deep link on Settle Up".
      this.sql.exec("ALTER TABLE members ADD COLUMN upi_vpa TEXT");
      this.setMeta(META_KEYS.schemaVersion, "7");
      current = "7";
    }
  }

  /** Has this group been created (vs. just addressed)? Drives `GROUP_NOT_FOUND`. */
  async exists(): Promise<boolean> {
    return this.meta(META_KEYS.name) !== null;
  }

  async initGroup(
    name: string,
    currency: string,
    creatorDisplayName: string,
    joinCode: string,
  ): Promise<{ member: Member; group: GroupSummary }> {
    if (await this.exists()) {
      throw new Error("Group already initialised");
    }
    const now = Date.now();
    const createdAt = isoSeconds(now);

    const accessToken = newAccessToken();
    this.setMeta(META_KEYS.name, name);
    this.setMeta(META_KEYS.currency, currency);
    this.setMeta(META_KEYS.joinCode, joinCode);
    this.setMeta(META_KEYS.createdAt, createdAt);
    this.setMeta(META_KEYS.schemaVersion, SCHEMA_VERSION);
    this.setMeta(META_KEYS.accessToken, accessToken);

    const member = this.insertMember(creatorDisplayName, now);
    return { member, group: { name, currency, createdAt, joinCode, accessToken } };
  }

  async addMember(displayName: string): Promise<{ member: Member }> {
    return { member: this.insertMember(displayName, Date.now()) };
  }

  /** Rename the group and/or change its default currency for *new* expenses.
   * Existing expenses/settlements keep their own currency (multi-currency:
   * the group currency is only a default — `DESIGN.md` §2). */
  async updateGroup(patch: { name?: string; currency?: string }): Promise<{ group: GroupSummary }> {
    if (patch.name !== undefined) this.setMeta(META_KEYS.name, patch.name);
    if (patch.currency !== undefined) this.setMeta(META_KEYS.currency, patch.currency);
    return { group: this.groupSummary() };
  }

  /** Update a member's display name and/or UPI VPA (`FEATURE_BACKLOG.md`
   * "UPI deep link on Settle Up") — the caller (`index.ts`) enforces that at
   * least one of the two is present. An empty-string `upiVpa` clears it. */
  async updateMember(id: string, patch: { displayName?: string; upiVpa?: string }): Promise<Result<{ member: Member }>> {
    const found = this.sql.exec<MemberRow>("SELECT id FROM members WHERE id = ?", id).toArray();
    if (found.length === 0) return fail("NOT_FOUND", `Member "${id}" is not in this group.`);
    if (patch.displayName !== undefined) {
      this.sql.exec("UPDATE members SET display_name = ? WHERE id = ?", patch.displayName, id);
    }
    if (patch.upiVpa !== undefined) {
      this.sql.exec("UPDATE members SET upi_vpa = ? WHERE id = ?", patch.upiVpa === "" ? null : patch.upiVpa, id);
    }
    const updated = this.sql.exec<MemberRow>("SELECT * FROM members WHERE id = ?", id).toArray()[0]!;
    return ok({ member: this.toMember(updated) });
  }

  /** Remove a member — only if they have no activity, aren't linked to an
   * account, and aren't the last member. Otherwise `MEMBER_IN_USE`. */
  async removeMember(id: string): Promise<Result<{ removed: true }>> {
    const rows = this.sql
      .exec<MemberRow>("SELECT id, identity_sub FROM members WHERE id = ?", id)
      .toArray();
    if (rows.length === 0) return fail("NOT_FOUND", `Member "${id}" is not in this group.`);
    if (rows[0]!.identity_sub !== null) {
      return fail("MEMBER_IN_USE", "This member is linked to an account. That account must be deleted instead.");
    }

    // Trashed (soft-deleted) rows don't count — from the group's point of
    // view they're already gone, same as if they'd never been on this member.
    const referenced = this.sql
      .exec<{ n: number }>(
        `SELECT
           (SELECT COUNT(*) FROM expenses WHERE payer_id = ? AND deleted_at IS NULL)
         + (SELECT COUNT(*) FROM expense_splits es JOIN expenses e ON e.id = es.expense_id
              WHERE es.member_id = ? AND e.deleted_at IS NULL)
         + (SELECT COUNT(*) FROM settlements WHERE (from_id = ? OR to_id = ?) AND deleted_at IS NULL) AS n`,
        id,
        id,
        id,
        id,
      )
      .toArray()[0]!.n;
    if (referenced > 0) {
      return fail("MEMBER_IN_USE", "This member is on expenses or settlements. Remove or reassign those first.");
    }

    const total = this.sql.exec<{ n: number }>("SELECT COUNT(*) AS n FROM members").toArray()[0]!.n;
    if (total <= 1) return fail("MEMBER_IN_USE", "A group must keep at least one member.");

    this.sql.exec("DELETE FROM members WHERE id = ?", id);
    return ok({ removed: true });
  }

  private groupSummary(): GroupSummary {
    return {
      name: this.requireMeta(META_KEYS.name),
      currency: this.requireMeta(META_KEYS.currency),
      createdAt: this.requireMeta(META_KEYS.createdAt),
      joinCode: this.requireMeta(META_KEYS.joinCode),
      accessToken: this.meta(META_KEYS.accessToken),
    };
  }

  // --- access token (ACCESS_TOKEN_PLAN.md) --------------------------------

  /** The current `access_token`, or `null` for a group created before this
   * feature shipped and never regenerated since. `requireGroup` in
   * `index.ts` treats `null` as "open access" — unchanged pre-existing
   * behavior, not a bypass. */
  async currentAccessToken(): Promise<string | null> {
    return this.meta(META_KEYS.accessToken);
  }

  /** Mint a fresh token, overwriting any existing one — every previously
   * shared link/code stops working immediately. Also the lazy-mint path for
   * a pre-existing group that never had one. */
  async regenerateAccessToken(): Promise<{ accessToken: string }> {
    const accessToken = newAccessToken();
    this.setMeta(META_KEYS.accessToken, accessToken);
    return { accessToken };
  }

  /** Whether `sub` (the composite `"<provider>:<sub>"` identity string) has a
   * claimed member in this group — the Bearer-session alternate credential
   * for a device that never saw the link/code itself (e.g. synced only via
   * `GET /api/auth/groups`). */
  async hasClaimedMember(sub: string): Promise<boolean> {
    const rows = this.sql
      .exec<{ id: string }>("SELECT id FROM members WHERE identity_sub = ? LIMIT 1", sub)
      .toArray();
    return rows.length > 0;
  }

  /** Every *other* claimed identity in this group — for push notification
   * fan-out (`FEATURE_BACKLOG.md` "Push notifications"): "notify on someone
   * else's action, never your own," so the acting identity is excluded, and
   * guests (`identity_sub IS NULL`) never appear — there's no device to
   * notify without a signed-in identity. */
  async claimedIdentitiesExcluding(actingSub: string): Promise<{ identities: string[] }> {
    const rows = this.sql
      .exec<{ identity_sub: string }>(
        "SELECT DISTINCT identity_sub FROM members WHERE identity_sub IS NOT NULL AND identity_sub != ?",
        actingSub,
      )
      .toArray();
    return { identities: rows.map((r) => r.identity_sub) };
  }

  // --- accounts / claim flow (ACCOUNTS_DESIGN.md §6) ----------------------
  // `GroupDO` is authoritative for membership↔identity; the Worker calls these
  // first, then updates the `UserDO` index. No wire route wired yet.

  /** The group's placeholder members (`identity_sub IS NULL`) — the list the
   * "this is me" picker shows. */
  async claimable(): Promise<{ members: Member[] }> {
    const rows = this.sql
      .exec<MemberRow>("SELECT * FROM members WHERE identity_sub IS NULL ORDER BY created_at ASC, rowid ASC")
      .toArray();
    return { members: rows.map((r) => this.toMember(r)) };
  }

  /** Link a placeholder member to a signed-in identity — `sub` is the
   * composite `"<provider>:<sub>"` string (`MANDATORY_LOGIN_PLAN.md` Part 2),
   * not a bare provider subject id. Idempotent: re-claiming the same member
   * with the same `sub` is a no-op success. */
  async claim(memberId: string, sub: string): Promise<Result<{ member: Member }>> {
    const rows = this.sql
      .exec<MemberRow>("SELECT id, display_name, identity_sub FROM members WHERE id = ?", memberId)
      .toArray();
    const row = rows[0];
    if (row === undefined) {
      return fail("UNKNOWN_MEMBER", `Member "${memberId}" is not in this group.`);
    }
    const member: Member = { id: row.id, displayName: row.display_name };

    if (row.identity_sub !== null) {
      return row.identity_sub === sub
        ? ok({ member })
        : fail("ALREADY_CLAIMED", "That member has already been linked to another account.");
    }

    const held = this.sql
      .exec<{ id: string }>("SELECT id FROM members WHERE identity_sub = ? LIMIT 1", sub)
      .toArray();
    if (held.length > 0) {
      return fail("IDENTITY_ALREADY_IN_GROUP", "You already have a membership in this group.");
    }

    this.sql.exec("UPDATE members SET identity_sub = ? WHERE id = ?", sub, memberId);
    return ok({ member });
  }

  /** Revert a member to a placeholder, but only if it's currently `sub`'s —
   * for account deletion (`ACCOUNTS_DESIGN.md` §11). Idempotent. */
  async unclaim(memberId: string, sub: string): Promise<void> {
    this.sql.exec(
      "UPDATE members SET identity_sub = NULL WHERE id = ? AND identity_sub = ?",
      memberId,
      sub,
    );
  }

  /** The Apple `sub` linked to a member, or `null` — for the `UserDO` index to
   * verify its entries against the source of truth. */
  async memberIdentity(memberId: string): Promise<{ sub: string | null }> {
    const rows = this.sql
      .exec<MemberRow>("SELECT identity_sub FROM members WHERE id = ?", memberId)
      .toArray();
    return { sub: rows.length > 0 ? rows[0]!.identity_sub : null };
  }

  /**
   * Cross-group settling (`FEATURE_BACKLOG.md`): the simplified-settlement edges
   * between the caller (`myMemberId`) and every *other claimed* member, per
   * currency. `sub` is checked against the caller's row so a stale `UserDO`
   * cache can't surface another identity's view — returns `null` if it no
   * longer matches. Only linked identities appear; guests are never listed.
   */
  async peerSettlements(
    sub: string,
    myMemberId: string,
  ): Promise<{ groupName: string; peers: PeerView[] } | null> {
    const mine = this.sql
      .exec<MemberRow>("SELECT id FROM members WHERE id = ? AND identity_sub = ?", myMemberId, sub)
      .toArray();
    if (mine.length === 0) return null;

    const groupName = this.requireMeta(META_KEYS.name);
    const claimed = this.sql
      .exec<MemberRow>(
        "SELECT id, display_name, identity_sub FROM members WHERE identity_sub IS NOT NULL AND id != ?",
        myMemberId,
      )
      .toArray();
    if (claimed.length === 0) return { groupName, peers: [] };

    const balances = computeBalances(this.readMembers(), this.readExpenses(), this.readSettlements());
    const plan = simplify(balances);

    const peers: PeerView[] = claimed.map((c) => ({
      memberId: c.id,
      sub: c.identity_sub as string,
      displayName: c.display_name,
      edges: plan
        .filter(
          (s) =>
            (s.fromId === myMemberId && s.toId === c.id) ||
            (s.fromId === c.id && s.toId === myMemberId),
        )
        .map((s) => ({
          currency: s.currency,
          amountMinor: s.amountMinor,
          youPay: s.fromId === myMemberId,
        })),
    }));

    return { groupName, peers };
  }

  async getState(): Promise<GroupStateResponse> {
    const members = this.readMembers();
    const expenses = this.readExpenses();
    const settlements = this.readSettlements();
    const balances = computeBalances(members, expenses, settlements);

    return {
      group: this.groupSummary(),
      members,
      expenses,
      settlements,
      balances,
      simplifiedSettlements: simplify(balances),
    };
  }

  async addExpense(req: AddExpenseRequest): Promise<Result<{ expense: Expense }>> {
    if (req.id !== undefined) {
      const existing = this.readExpenseById(req.id);
      if (existing !== null) return ok({ expense: existing }); // idempotent replay
    }

    const invalid = this.validateExpense(req);
    if (invalid !== null) return invalid;

    const id = req.id ?? newRecordId();
    this.writeExpense(id, Date.now(), req);

    const expense = this.readExpenseById(id);
    if (expense === null) throw new Error("Expense vanished immediately after insert");
    return ok({ expense });
  }

  /**
   * Replace an existing expense wholesale (`PUT`, `DESIGN.md` §2). `created_at`
   * is preserved so the row keeps its place in the activity feed. Balances are
   * derived on read, so nothing else needs touching. `NOT_FOUND` → 404.
   */
  async updateExpense(id: string, req: AddExpenseRequest): Promise<Result<{ expense: Expense }>> {
    if (this.readExpenseById(id) === null) {
      return fail("NOT_FOUND", `Expense "${id}" is not in this group.`);
    }
    const invalid = this.validateExpense(req);
    if (invalid !== null) return invalid;

    const createdAt = this.originalCreatedAt("expenses", id);
    this.sql.exec("DELETE FROM expenses WHERE id = ?", id);
    this.sql.exec("DELETE FROM expense_splits WHERE expense_id = ?", id);
    this.writeExpense(id, createdAt, req);

    const expense = this.readExpenseById(id);
    if (expense === null) throw new Error("Expense vanished immediately after update");
    return ok({ expense });
  }

  /** Soft-delete: stamps `deleted_at`/`deleted_by` instead of a real `DELETE`
   * (`FEATURE_BACKLOG.md`) — splits are left alone so Restore can reconstruct
   * the expense exactly. Idempotent both ways: deleting an id that never
   * existed is a no-op `{ deleted: false }`; deleting one that's already
   * trashed is a no-op `{ deleted: true }` that doesn't touch the original
   * `deleted_at`/`deleted_by`. `deletedBy` is a memberId, trusted at face
   * value like every other id in this trust model — not cryptographically
   * verified against a session. */
  async deleteExpense(id: string, deletedBy?: string): Promise<{ deleted: boolean }> {
    const row = this.expenseRow(id);
    if (row === null) return { deleted: false };
    if (row.deleted_at === null) {
      this.sql.exec("UPDATE expenses SET deleted_at = ?, deleted_by = ? WHERE id = ?", Date.now(), deletedBy ?? null, id);
    }
    return { deleted: true };
  }

  /** Undo a soft delete. `NOT_FOUND` if the id doesn't exist or isn't
   * currently trashed (already active, or never existed). */
  async restoreExpense(id: string): Promise<Result<{ expense: Expense }>> {
    const row = this.expenseRow(id);
    if (row === null || row.deleted_at === null) {
      return fail("NOT_FOUND", `Expense "${id}" is not in the trash.`);
    }
    this.sql.exec("UPDATE expenses SET deleted_at = NULL, deleted_by = NULL WHERE id = ?", id);
    const expense = this.readExpenseById(id);
    if (expense === null) throw new Error("Expense vanished immediately after restore");
    return ok({ expense });
  }

  async addSettlement(req: AddSettlementRequest): Promise<Result<{ settlement: Settlement }>> {
    if (req.id !== undefined) {
      const existing = this.readSettlementById(req.id);
      if (existing !== null) return ok({ settlement: existing });
    }

    const invalid = this.validateSettlement(req);
    if (invalid !== null) return invalid;

    const id = req.id ?? newRecordId();
    this.writeSettlement(id, Date.now(), req);

    const settlement = this.readSettlementById(id);
    if (settlement === null) throw new Error("Settlement vanished immediately after insert");
    return ok({ settlement });
  }

  /** Replace an existing settlement wholesale. `settled_at` is preserved.
   * `NOT_FOUND` → 404. */
  async updateSettlement(id: string, req: AddSettlementRequest): Promise<Result<{ settlement: Settlement }>> {
    if (this.readSettlementById(id) === null) {
      return fail("NOT_FOUND", `Settlement "${id}" is not in this group.`);
    }
    const invalid = this.validateSettlement(req);
    if (invalid !== null) return invalid;

    const settledAt = this.originalCreatedAt("settlements", id);
    this.sql.exec("DELETE FROM settlements WHERE id = ?", id);
    this.writeSettlement(id, settledAt, req);

    const settlement = this.readSettlementById(id);
    if (settlement === null) throw new Error("Settlement vanished immediately after update");
    return ok({ settlement });
  }

  /** Soft-delete — see `deleteExpense` for the full semantics (same idempotent
   * shape, same trust model for `deletedBy`). */
  async deleteSettlement(id: string, deletedBy?: string): Promise<{ deleted: boolean }> {
    const row = this.settlementRow(id);
    if (row === null) return { deleted: false };
    if (row.deleted_at === null) {
      this.sql.exec("UPDATE settlements SET deleted_at = ?, deleted_by = ? WHERE id = ?", Date.now(), deletedBy ?? null, id);
    }
    return { deleted: true };
  }

  /** Undo a soft delete. `NOT_FOUND` if the id doesn't exist or isn't
   * currently trashed. */
  async restoreSettlement(id: string): Promise<Result<{ settlement: Settlement }>> {
    const row = this.settlementRow(id);
    if (row === null || row.deleted_at === null) {
      return fail("NOT_FOUND", `Settlement "${id}" is not in the trash.`);
    }
    this.sql.exec("UPDATE settlements SET deleted_at = NULL, deleted_by = NULL WHERE id = ?", id);
    const settlement = this.readSettlementById(id);
    if (settlement === null) throw new Error("Settlement vanished immediately after restore");
    return ok({ settlement });
  }

  /** Soft-deleted expenses/settlements, newest-deleted first
   * (`FEATURE_BACKLOG.md` "Recently Deleted"). No purge job — kept forever
   * until there's a reason not to (SQLite storage is cheap). */
  async trash(): Promise<{ expenses: Expense[]; settlements: Settlement[] }> {
    const expenseRows = this.sql
      .exec<ExpenseRow>("SELECT * FROM expenses WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC, rowid DESC")
      .toArray();
    const splits = this.sql.exec<SplitRow>("SELECT * FROM expense_splits").toArray();
    const settlementRows = this.sql
      .exec<SettlementRow>("SELECT * FROM settlements WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC, rowid DESC")
      .toArray();
    return {
      expenses: expenseRows.map((e) => this.toExpense(e, splits)),
      settlements: settlementRows.map((s) => this.toSettlement(s)),
    };
  }

  // --- add/edit shared internals ----------------------------------------

  private validateExpense(req: AddExpenseRequest): Result<never> | null {
    try {
      assertPositiveAmount(req.amountMinor);
      const memberIds = new Set(this.readMembers().map((m) => m.id));
      assertMembersExist([req.payerId, ...req.splits.map((s) => s.memberId)], memberIds);
      assertSplitsSum(req.amountMinor, req.splits);
      return null;
    } catch (e) {
      if (e instanceof ValidationFailure) return fail(e.code, e.message);
      throw e;
    }
  }

  private validateSettlement(req: AddSettlementRequest): Result<never> | null {
    if (req.fromId === req.toId) {
      return fail("UNKNOWN_MEMBER", "A settlement cannot be from a member to themselves.");
    }
    try {
      assertPositiveAmount(req.amountMinor);
      const memberIds = new Set(this.readMembers().map((m) => m.id));
      assertMembersExist([req.fromId, req.toId], memberIds);
      return null;
    } catch (e) {
      if (e instanceof ValidationFailure) return fail(e.code, e.message);
      throw e;
    }
  }

  private writeExpense(id: string, createdAt: number, req: AddExpenseRequest): void {
    const currency = req.currency ?? this.requireMeta(META_KEYS.currency);
    this.sql.exec(
      "INSERT INTO expenses (id, payer_id, amount_minor, description, expense_date, split_type, created_at, category, category_icon, currency) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
      id,
      req.payerId,
      req.amountMinor,
      req.description,
      req.date,
      req.splitType,
      createdAt,
      req.category ?? null,
      req.categoryIcon ?? null,
      currency,
    );
    for (const s of req.splits) {
      this.sql.exec(
        "INSERT INTO expense_splits (expense_id, member_id, amount_minor) VALUES (?, ?, ?)",
        id,
        s.memberId,
        s.amountMinor,
      );
    }
  }

  private writeSettlement(id: string, settledAt: number, req: AddSettlementRequest): void {
    const currency = req.currency ?? this.requireMeta(META_KEYS.currency);
    this.sql.exec(
      "INSERT INTO settlements (id, from_id, to_id, amount_minor, settled_at, currency) VALUES (?, ?, ?, ?, ?, ?)",
      id,
      req.fromId,
      req.toId,
      req.amountMinor,
      settledAt,
      currency,
    );
  }

  /** The `created_at` / `settled_at` of a row about to be rewritten, so an edit
   * doesn't reorder the activity feed. Read before the DELETE. */
  private originalCreatedAt(table: "expenses" | "settlements", id: string): number {
    const column = table === "expenses" ? "created_at" : "settled_at";
    const rows = this.sql
      .exec<{ ts: number }>(`SELECT ${column} AS ts FROM ${table} WHERE id = ?`, id)
      .toArray();
    return rows.length > 0 ? rows[0]!.ts : Date.now();
  }

  // --- persistence helpers -------------------------------------------------

  private meta(key: string): string | null {
    const rows = this.sql
      .exec<{ value: string }>("SELECT value FROM group_meta WHERE key = ?", key)
      .toArray();
    return rows.length > 0 ? rows[0]!.value : null;
  }

  private requireMeta(key: string): string {
    const value = this.meta(key);
    if (value === null) throw new Error(`Missing group_meta row: ${key}`);
    return value;
  }

  private setMeta(key: string, value: string): void {
    this.sql.exec(
      "INSERT INTO group_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
      key,
      value,
    );
  }

  private insertMember(displayName: string, createdAt: number): Member {
    const id = newMemberId();
    this.sql.exec(
      "INSERT INTO members (id, display_name, created_at) VALUES (?, ?, ?)",
      id,
      displayName,
      createdAt,
    );
    return { id, displayName };
  }

  private readMembers(): Member[] {
    return this.sql
      .exec<MemberRow>("SELECT * FROM members ORDER BY created_at ASC, rowid ASC")
      .toArray()
      .map((r) => this.toMember(r));
  }

  /** Omits `upiVpa` entirely when unset, matching the `category?` wire shape. */
  private toMember(row: MemberRow): Member {
    return {
      id: row.id,
      displayName: row.display_name,
      ...(row.upi_vpa != null ? { upiVpa: row.upi_vpa } : {}),
    };
  }

  /** Active (non-trashed) expenses only — `getState`, balances, idempotent-add
   * and update's existence check all go through this. `trash()` and the raw
   * `expenseRow` helper are the only paths that ever see a soft-deleted row. */
  private readExpenses(): Expense[] {
    const rows = this.sql
      .exec<ExpenseRow>("SELECT * FROM expenses WHERE deleted_at IS NULL ORDER BY created_at ASC, rowid ASC")
      .toArray();
    const splits = this.sql.exec<SplitRow>("SELECT * FROM expense_splits").toArray();
    return rows.map((e) => this.toExpense(e, splits));
  }

  private readExpenseById(id: string): Expense | null {
    const rows = this.sql
      .exec<ExpenseRow>("SELECT * FROM expenses WHERE id = ? AND deleted_at IS NULL", id)
      .toArray();
    if (rows.length === 0) return null;
    const splits = this.sql
      .exec<SplitRow>("SELECT * FROM expense_splits WHERE expense_id = ?", id)
      .toArray();
    return this.toExpense(rows[0]!, splits);
  }

  /** Raw row lookup regardless of trashed state — for `deleteExpense` /
   * `restoreExpense`, which need to see a row whichever state it's in. */
  private expenseRow(id: string): ExpenseRow | null {
    const rows = this.sql.exec<ExpenseRow>("SELECT * FROM expenses WHERE id = ?", id).toArray();
    return rows.length > 0 ? rows[0]! : null;
  }

  private toExpense(e: ExpenseRow, allSplits: SplitRow[]): Expense {
    return {
      id: e.id,
      payerId: e.payer_id,
      amountMinor: e.amount_minor,
      currency: e.currency,
      description: e.description,
      date: e.expense_date,
      splitType: e.split_type,
      splits: allSplits
        .filter((s) => s.expense_id === e.id)
        .map((s) => ({ memberId: s.member_id, amountMinor: s.amount_minor })),
      // Omit the keys entirely when unset (nullable columns → `undefined` →
      // dropped by JSON.stringify), matching the `category?` wire shape.
      ...(e.category != null ? { category: e.category } : {}),
      ...(e.category_icon != null ? { categoryIcon: e.category_icon } : {}),
      ...(e.deleted_at != null ? { deletedAt: isoSeconds(e.deleted_at) } : {}),
      ...(e.deleted_by != null ? { deletedBy: e.deleted_by } : {}),
    };
  }

  /** Active (non-trashed) settlements only — see `readExpenses`. */
  private readSettlements(): Settlement[] {
    return this.sql
      .exec<SettlementRow>("SELECT * FROM settlements WHERE deleted_at IS NULL ORDER BY settled_at ASC, rowid ASC")
      .toArray()
      .map((s) => this.toSettlement(s));
  }

  private readSettlementById(id: string): Settlement | null {
    const rows = this.sql
      .exec<SettlementRow>("SELECT * FROM settlements WHERE id = ? AND deleted_at IS NULL", id)
      .toArray();
    return rows.length > 0 ? this.toSettlement(rows[0]!) : null;
  }

  /** Raw row lookup regardless of trashed state — see `expenseRow`. */
  private settlementRow(id: string): SettlementRow | null {
    const rows = this.sql.exec<SettlementRow>("SELECT * FROM settlements WHERE id = ?", id).toArray();
    return rows.length > 0 ? rows[0]! : null;
  }

  private toSettlement(s: SettlementRow): Settlement {
    return {
      id: s.id,
      fromId: s.from_id,
      toId: s.to_id,
      amountMinor: s.amount_minor,
      currency: s.currency,
      date: isoSeconds(s.settled_at),
      ...(s.deleted_at != null ? { deletedAt: isoSeconds(s.deleted_at) } : {}),
      ...(s.deleted_by != null ? { deletedBy: s.deleted_by } : {}),
    };
  }
}
