import { DurableObject } from "cloudflare:workers";
import { computeBalances } from "./lib/balances.ts";
import { newMemberId, newRecordId } from "./lib/ids.ts";
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
}>;
type ExpenseRow = Row<{
  id: string;
  payer_id: string;
  amount_minor: number;
  description: string;
  expense_date: string;
  split_type: "equal" | "exact" | "percentage";
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
}>;

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
    const current = this.meta(META_KEYS.schemaVersion);
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

    this.setMeta(META_KEYS.name, name);
    this.setMeta(META_KEYS.currency, currency);
    this.setMeta(META_KEYS.joinCode, joinCode);
    this.setMeta(META_KEYS.createdAt, createdAt);
    this.setMeta(META_KEYS.schemaVersion, SCHEMA_VERSION);

    const member = this.insertMember(creatorDisplayName, now);
    return { member, group: { name, currency, createdAt, joinCode } };
  }

  async addMember(displayName: string): Promise<{ member: Member }> {
    return { member: this.insertMember(displayName, Date.now()) };
  }

  async getState(): Promise<GroupStateResponse> {
    const members = this.readMembers();
    const expenses = this.readExpenses();
    const settlements = this.readSettlements();
    const balances = computeBalances(members, expenses, settlements);

    return {
      group: {
        name: this.requireMeta(META_KEYS.name),
        currency: this.requireMeta(META_KEYS.currency),
        createdAt: this.requireMeta(META_KEYS.createdAt),
        joinCode: this.requireMeta(META_KEYS.joinCode),
      },
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

    try {
      assertPositiveAmount(req.amountMinor);
      const memberIds = new Set(this.readMembers().map((m) => m.id));
      assertMembersExist([req.payerId, ...req.splits.map((s) => s.memberId)], memberIds);
      assertSplitsSum(req.amountMinor, req.splits);
    } catch (e) {
      if (e instanceof ValidationFailure) return fail(e.code, e.message);
      throw e;
    }

    const id = req.id ?? newRecordId();
    const now = Date.now();

    this.sql.exec(
      "INSERT INTO expenses (id, payer_id, amount_minor, description, expense_date, split_type, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
      id,
      req.payerId,
      req.amountMinor,
      req.description,
      req.date,
      req.splitType,
      now,
    );
    for (const s of req.splits) {
      this.sql.exec(
        "INSERT INTO expense_splits (expense_id, member_id, amount_minor) VALUES (?, ?, ?)",
        id,
        s.memberId,
        s.amountMinor,
      );
    }

    const expense = this.readExpenseById(id);
    if (expense === null) throw new Error("Expense vanished immediately after insert");
    return ok({ expense });
  }

  async addSettlement(req: AddSettlementRequest): Promise<Result<{ settlement: Settlement }>> {
    if (req.id !== undefined) {
      const existing = this.readSettlementById(req.id);
      if (existing !== null) return ok({ settlement: existing });
    }

    if (req.fromId === req.toId) {
      return fail("UNKNOWN_MEMBER", "A settlement cannot be from a member to themselves.");
    }
    try {
      assertPositiveAmount(req.amountMinor);
      const memberIds = new Set(this.readMembers().map((m) => m.id));
      assertMembersExist([req.fromId, req.toId], memberIds);
    } catch (e) {
      if (e instanceof ValidationFailure) return fail(e.code, e.message);
      throw e;
    }

    const id = req.id ?? newRecordId();
    const now = Date.now();
    this.sql.exec(
      "INSERT INTO settlements (id, from_id, to_id, amount_minor, settled_at) VALUES (?, ?, ?, ?, ?)",
      id,
      req.fromId,
      req.toId,
      req.amountMinor,
      now,
    );

    const settlement = this.readSettlementById(id);
    if (settlement === null) throw new Error("Settlement vanished immediately after insert");
    return ok({ settlement });
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
      .exec<MemberRow>("SELECT id, display_name FROM members ORDER BY created_at ASC, rowid ASC")
      .toArray()
      .map((r) => ({ id: r.id, displayName: r.display_name }));
  }

  private readExpenses(): Expense[] {
    const rows = this.sql
      .exec<ExpenseRow>("SELECT * FROM expenses ORDER BY created_at ASC, rowid ASC")
      .toArray();
    const splits = this.sql.exec<SplitRow>("SELECT * FROM expense_splits").toArray();
    return rows.map((e) => this.toExpense(e, splits));
  }

  private readExpenseById(id: string): Expense | null {
    const rows = this.sql.exec<ExpenseRow>("SELECT * FROM expenses WHERE id = ?", id).toArray();
    if (rows.length === 0) return null;
    const splits = this.sql
      .exec<SplitRow>("SELECT * FROM expense_splits WHERE expense_id = ?", id)
      .toArray();
    return this.toExpense(rows[0]!, splits);
  }

  private toExpense(e: ExpenseRow, allSplits: SplitRow[]): Expense {
    return {
      id: e.id,
      payerId: e.payer_id,
      amountMinor: e.amount_minor,
      description: e.description,
      date: e.expense_date,
      splitType: e.split_type,
      splits: allSplits
        .filter((s) => s.expense_id === e.id)
        .map((s) => ({ memberId: s.member_id, amountMinor: s.amount_minor })),
    };
  }

  private readSettlements(): Settlement[] {
    return this.sql
      .exec<SettlementRow>("SELECT * FROM settlements ORDER BY settled_at ASC, rowid ASC")
      .toArray()
      .map((s) => this.toSettlement(s));
  }

  private readSettlementById(id: string): Settlement | null {
    const rows = this.sql.exec<SettlementRow>("SELECT * FROM settlements WHERE id = ?", id).toArray();
    return rows.length > 0 ? this.toSettlement(rows[0]!) : null;
  }

  private toSettlement(s: SettlementRow): Settlement {
    return {
      id: s.id,
      fromId: s.from_id,
      toId: s.to_id,
      amountMinor: s.amount_minor,
      date: isoSeconds(s.settled_at),
    };
  }
}
