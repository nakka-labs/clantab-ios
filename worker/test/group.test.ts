import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";

function group(name: string) {
  return env.GROUP_DO.get(env.GROUP_DO.idFromName(name));
}

describe("GroupDO", () => {
  it("exists() flips from false to true once initGroup runs", async () => {
    const g = group("g-exists");
    expect(await g.exists()).toBe(false);
    await g.initGroup("Trip", "USD", "Ana", "ABC234");
    expect(await g.exists()).toBe(true);
  });

  it("getState returns the summary (with joinCode), members oldest-first, and no balances", async () => {
    const g = group("g-state");
    await g.initGroup("Trip", "USD", "Ana", "XYZ234");
    await g.addMember("Ben");

    const state = await g.getState();
    expect(state.group).toMatchObject({ name: "Trip", currency: "USD", joinCode: "XYZ234" });
    expect(state.members.map((m) => m.displayName)).toEqual(["Ana", "Ben"]);
    expect(state.balances).toEqual([]); // nothing spent yet
  });

  it("orders expenses and settlements by insertion time", async () => {
    const g = group("g-order");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ORD234");
    const { member: ben } = await g.addMember("Ben");

    for (const desc of ["first", "second", "third"]) {
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 200 }],
        amountMinor: 200,
        description: desc,
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: ana.id, amountMinor: 100 },
          { memberId: ben.id, amountMinor: 100 },
        ],
      });
      expect(r.ok).toBe(true);
    }

    const state = await g.getState();
    expect(state.expenses.map((e) => e.description)).toEqual(["first", "second", "third"]);
  });

  it("addExpense with a repeated id is an idempotent no-op", async () => {
    const g = group("g-idem");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "IDM234");
    const { member: ben } = await g.addMember("Ben");

    const req = {
      id: "fixed-id-1",
      payers: [{ memberId: ana.id, amountMinor: 200 }],
      amountMinor: 200,
      description: "Lunch",
      date: "2026-01-01T00:00:00Z",
      splitType: "equal" as const,
      splits: [
        { memberId: ana.id, amountMinor: 100 },
        { memberId: ben.id, amountMinor: 100 },
      ],
    };
    const a = await g.addExpense(req);
    const b = await g.addExpense(req);
    expect(a).toEqual(b);
    expect((await g.getState()).expenses).toHaveLength(1);
  });

  it("records a percentage-split expense (splits pre-resolved to minor units)", async () => {
    const g = group("g-percent");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PCT234");
    const { member: ben } = await g.addMember("Ben");

    const r = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 1000 }],
      amountMinor: 1000,
      description: "Dinner (60/40)",
      date: "2026-01-01T00:00:00Z",
      splitType: "percentage",
      splits: [
        { memberId: ana.id, amountMinor: 600 },
        { memberId: ben.id, amountMinor: 400 },
      ],
    });
    expect(r.ok).toBe(true);
    const state = await g.getState();
    expect(state.expenses[0]).toMatchObject({ splitType: "percentage", currency: "USD" });
    expect(state.balances).toEqual([
      { memberId: ana.id, currency: "USD", netMinor: 400 }, // paid 1000, own share 600
      { memberId: ben.id, currency: "USD", netMinor: -400 },
    ]);
  });

  describe("itemized-split expense (FEATURE_BACKLOG.md — itemized expense entry)", () => {
    it("records the line items and balances off the pre-resolved splits", async () => {
      const g = group("g-items-ok");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ITM234");
      const { member: ben } = await g.addMember("Ben");

      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "Groceries",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [
          { memberId: ana.id, amountMinor: 700 },
          { memberId: ben.id, amountMinor: 300 },
        ],
        items: [
          { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [ana.id, ben.id] },
          { id: "li2", name: "Wine", amountMinor: 400, participantIds: [ana.id] },
        ],
      });
      expect(r.ok).toBe(true);

      const state = await g.getState();
      expect(state.expenses[0]).toMatchObject({ splitType: "itemized", currency: "USD" });
      expect(state.expenses[0]!.items).toEqual([
        { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [ana.id, ben.id] },
        { id: "li2", name: "Wine", amountMinor: 400, participantIds: [ana.id] },
      ]);
      expect(state.balances).toEqual([
        { memberId: ana.id, currency: "USD", netMinor: 300 }, // paid 1000, own share 700
        { memberId: ben.id, currency: "USD", netMinor: -300 },
      ]);
    });

    it("rejects items that don't sum to the amount", async () => {
      const g = group("g-items-sum");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ITM235");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 1000 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: ana.id, amountMinor: 1000 }],
        items: [{ id: "li1", name: "Only", amountMinor: 900, participantIds: [ana.id] }],
      });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("SPLIT_MISMATCH");
    });

    it("rejects an item whose participant isn't in the group", async () => {
      const g = group("g-items-ghost");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ITM236");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 500 }],
        amountMinor: 500,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: ana.id, amountMinor: 500 }],
        items: [{ id: "li1", name: "Thing", amountMinor: 500, participantIds: [ana.id, "ghost"] }],
      });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("UNKNOWN_MEMBER");
    });

    it("an edit can replace the itemization wholesale", async () => {
      const g = group("g-items-edit");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ITM237");
      const { member: ben } = await g.addMember("Ben");
      const added = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 600 }],
        amountMinor: 600,
        description: "Lunch",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [
          { memberId: ana.id, amountMinor: 300 },
          { memberId: ben.id, amountMinor: 300 },
        ],
        items: [{ id: "a", name: "Shared", amountMinor: 600, participantIds: [ana.id, ben.id] }],
      });
      expect(added.ok).toBe(true);
      const id = added.ok ? added.value.expense.id : "";

      const edited = await g.updateExpense(id, {
        payers: [{ memberId: ana.id, amountMinor: 600 }],
        amountMinor: 600,
        description: "Lunch",
        date: "2026-01-01T00:00:00Z",
        splitType: "exact",
        splits: [
          { memberId: ana.id, amountMinor: 200 },
          { memberId: ben.id, amountMinor: 400 },
        ],
      });
      expect(edited.ok).toBe(true);
      const state = await g.getState();
      expect(state.expenses[0]).toMatchObject({ splitType: "exact" });
      expect(state.expenses[0]!.items).toBeUndefined();
    });
  });

  describe('itemized tax/tip (CHECKLIST.md "Tax/tip proportional split on itemized expenses")', () => {
    it("stores tax/tip alongside the items and balances off the pre-resolved (already-proportional) splits", async () => {
      const g = group("g-taxtip-ok");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TXT234");
      const { member: ben } = await g.addMember("Ben");

      // Ana ordered 750, Ben 250 — a 3:1 item split. 60 tax + 40 tip (100
      // total), split 3:1 by the client → Ana +75, Ben +25 (`ClanTabKit`'s
      // `Validation.itemizedSplit` is what actually computes this; the
      // server only checks the items+tax+tip sum and that `splits` agrees).
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 1100 }],
        amountMinor: 1100,
        description: "Dinner",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [
          { memberId: ana.id, amountMinor: 825 },
          { memberId: ben.id, amountMinor: 275 },
        ],
        items: [
          { id: "li1", name: "Steak", amountMinor: 750, participantIds: [ana.id] },
          { id: "li2", name: "Salad", amountMinor: 250, participantIds: [ben.id] },
        ],
        taxMinor: 60,
        tipMinor: 40,
      });
      expect(r.ok).toBe(true);

      const state = await g.getState();
      expect(state.expenses[0]).toMatchObject({ splitType: "itemized", taxMinor: 60, tipMinor: 40 });
      expect(state.balances).toEqual([
        { memberId: ana.id, currency: "USD", netMinor: 275 }, // paid 1100, own share 825
        { memberId: ben.id, currency: "USD", netMinor: -275 },
      ]);
    });

    it("omits taxMinor/tipMinor entirely when neither was sent", async () => {
      const g = group("g-taxtip-absent");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TXT235");
      await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 500 }],
        amountMinor: 500,
        description: "Snacks",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: ana.id, amountMinor: 500 }],
        items: [{ id: "li1", name: "Chips", amountMinor: 500, participantIds: [ana.id] }],
      });
      const state = await g.getState();
      expect(state.expenses[0]!.taxMinor).toBeUndefined();
      expect(state.expenses[0]!.tipMinor).toBeUndefined();
    });

    it("rejects items + tax + tip not summing to the amount", async () => {
      const g = group("g-taxtip-sum");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TXT236");
      // Items (900) + tax (60) + tip (40) = 1000, but the expense claims 900.
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 900 }],
        amountMinor: 900,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: ana.id, amountMinor: 900 }],
        items: [{ id: "li1", name: "Only", amountMinor: 900, participantIds: [ana.id] }],
        taxMinor: 60,
        tipMinor: 40,
      });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("SPLIT_MISMATCH");
    });

    it("rejects a negative tax or tip", async () => {
      const g = group("g-taxtip-negative");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TXT237");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 940 }],
        amountMinor: 940,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "itemized",
        splits: [{ memberId: ana.id, amountMinor: 940 }],
        items: [{ id: "li1", name: "Only", amountMinor: 1000, participantIds: [ana.id] }],
        taxMinor: -60,
      });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("INVALID_AMOUNT");
    });
  });

  describe('multiple payers (CHECKLIST.md "Multiple payers on one expense")', () => {
    it("credits each payer their own contribution, not the whole amount", async () => {
      const g = group("g-payers-ok");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PAY234");
      const { member: ben } = await g.addMember("Ben");
      const { member: cara } = await g.addMember("Cara");

      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 700 }, { memberId: ben.id, amountMinor: 300 }],
        amountMinor: 1000,
        description: "Groceries",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: ana.id, amountMinor: 334 },
          { memberId: ben.id, amountMinor: 333 },
          { memberId: cara.id, amountMinor: 333 },
        ],
      });
      expect(r.ok).toBe(true);

      const state = await g.getState();
      expect(state.expenses[0]!.payers).toEqual([
        { memberId: ana.id, amountMinor: 700 },
        { memberId: ben.id, amountMinor: 300 },
      ]);
      expect(state.balances).toEqual([
        { memberId: ana.id, currency: "USD", netMinor: 366 }, // paid 700, owes 334
        { memberId: ben.id, currency: "USD", netMinor: -33 }, // paid 300, owes 333
        { memberId: cara.id, currency: "USD", netMinor: -333 },
      ]);
    });

    it("rejects payers that don't sum to the amount", async () => {
      const g = group("g-payers-sum");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PAY235");
      const { member: ben } = await g.addMember("Ben");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 600 }, { memberId: ben.id, amountMinor: 300 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 500 }, { memberId: ben.id, amountMinor: 500 }],
      });
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("SPLIT_MISMATCH");
    });

    it("rejects a payer who isn't in the group, and an empty payers array", async () => {
      const g = group("g-payers-ghost");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PAY236");
      const ghost = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 500 }, { memberId: "ghost", amountMinor: 500 }],
        amountMinor: 1000,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 1000 }],
      });
      expect(ghost.ok).toBe(false);
      if (!ghost.ok) expect(ghost.error.code).toBe("UNKNOWN_MEMBER");

      const empty = await g.addExpense({
        payers: [],
        amountMinor: 100,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 100 }],
      });
      expect(empty.ok).toBe(false);
      if (!empty.ok) expect(empty.error.code).toBe("SPLIT_MISMATCH");
    });

    it("removeMember blocks removing a non-primary payer, not just the first one", async () => {
      const g = group("g-payers-remove");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PAY237");
      const { member: ben } = await g.addMember("Ben");
      await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 700 }, { memberId: ben.id, amountMinor: 300 }],
        amountMinor: 1000,
        description: "Groceries",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 500 }, { memberId: ben.id, amountMinor: 500 }],
      });

      // Ben is only the *second* payer (payer_id on the row is Ana's, the
      // primary/placeholder) — the plain payer_id check alone would miss him.
      const removed = await g.removeMember(ben.id);
      expect(removed.ok).toBe(false);
      if (!removed.ok) expect(removed.error.code).toBe("MEMBER_IN_USE");
    });

    it("a single payer never gets a redundant payers JSON blob", async () => {
      const g = group("g-payers-single-storage");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "PAY238");
      await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }],
        amountMinor: 100,
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 100 }],
      });
      await runInDurableObject(g, (_instance, state) => {
        const row = state.storage.sql
          .exec<{ payers: string | null; payer_id: string }>("SELECT payers, payer_id FROM expenses")
          .toArray()[0]!;
        expect(row.payers).toBeNull();
        expect(row.payer_id).toBe(ana.id);
      });
    });
  });

  it("migrate() upgrades a v1 expenses table through every schema version", async () => {
    const g = group("g-migrate");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "MIG234");
    await g.addMember("Ben");

    // Rewind this DO to the original v1 shape: narrow CHECK, no category
    // columns, schema_version 1 — then let migrate() walk it forward.
    await runInDurableObject(g, (instance, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE expenses");
      sql.exec("DROP TABLE settlements");
      sql.exec("DROP TABLE members");
      sql.exec(`CREATE TABLE expenses (
        id           TEXT PRIMARY KEY,
        payer_id     TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        description  TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        split_type   TEXT NOT NULL CHECK (split_type IN ('equal','exact')),
        created_at   INTEGER NOT NULL
      )`);
      sql.exec(`CREATE TABLE settlements (
        id           TEXT PRIMARY KEY,
        from_id      TEXT NOT NULL,
        to_id        TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        settled_at   INTEGER NOT NULL
      )`);
      sql.exec(`CREATE TABLE members (
        id           TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        created_at   INTEGER NOT NULL
      )`);
      sql.exec("INSERT INTO members VALUES (?, 'Ana', 1)", ana.id);
      sql.exec(
        "INSERT INTO expenses VALUES ('old-1', ?, 100, 'Legacy', '2026-01-01T00:00:00Z', 'equal', 1)",
        ana.id,
      );
      sql.exec("UPDATE group_meta SET value = '1' WHERE key = 'schema_version'");
      (instance as unknown as { migrate(): void }).migrate();

      const version = sql
        .exec<{ value: string }>("SELECT value FROM group_meta WHERE key = 'schema_version'")
        .toArray()[0]?.value;
      expect(version).toBe("14");

      // The legacy expense survived the v2 + v8 + v11 rebuilds, gained null
      // category columns, had its currency backfilled from the group (USD),
      // gained null deleted_at/deleted_by (v6), a null `items` column (v8), a
      // null `attachments` column (v10), a null `shares` column (v11), a null
      // `payers` column (v13), and null `tax_minor`/`tip_minor` columns (v14).
      const legacy = sql
        .exec<{
          category: string | null;
          category_icon: string | null;
          currency: string;
          deleted_at: number | null;
          deleted_by: string | null;
          items: string | null;
          attachments: string | null;
          shares: string | null;
          payers: string | null;
          tax_minor: number | null;
          tip_minor: number | null;
        }>(
          "SELECT category, category_icon, currency, deleted_at, deleted_by, items, attachments, shares, payers, tax_minor, tip_minor FROM expenses WHERE id = 'old-1'",
        )
        .toArray()[0];
      expect(legacy).toEqual({
        category: null,
        category_icon: null,
        attachments: null,
        currency: "USD",
        deleted_at: null,
        deleted_by: null,
        items: null,
        payers: null,
        shares: null,
        tax_minor: null,
        tip_minor: null,
      });

      // The legacy member gained a null identity_sub (v5) — i.e. it's a
      // placeholder — a null upi_vpa (v7), and a null avatar_key (v9).
      const member = sql
        .exec<{ identity_sub: string | null; upi_vpa: string | null; avatar_key: string | null }>(
          "SELECT identity_sub, upi_vpa, avatar_key FROM members WHERE id = ?",
          ana.id,
        )
        .toArray()[0];
      expect(member).toEqual({ identity_sub: null, upi_vpa: null, avatar_key: null });
    });

    // percentage (needs v2), category (needs v3), currency (needs v4) post-migration.
    const r = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 500 }],
      amountMinor: 500,
      currency: "EUR",
      description: "Post-migration",
      date: "2026-01-01T00:00:00Z",
      splitType: "percentage",
      splits: [{ memberId: ana.id, amountMinor: 500 }],
      category: "Travel",
      categoryIcon: "airplane",
    });
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value.expense).toMatchObject({ category: "Travel", categoryIcon: "airplane", currency: "EUR" });
    }

    // itemized (needs the v8 CHECK widen + items column) post-migration. Only
    // Ana survived the rewind above, so a single-participant itemization.
    const ri = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 1000 }],
      amountMinor: 1000,
      description: "Groceries",
      date: "2026-01-02T00:00:00Z",
      splitType: "itemized",
      splits: [{ memberId: ana.id, amountMinor: 1000 }],
      items: [
        { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [ana.id] },
        { id: "li2", name: "Wine", amountMinor: 400, participantIds: [ana.id] },
      ],
    });
    expect(ri.ok).toBe(true);
    if (ri.ok) {
      expect(ri.value.expense.splitType).toBe("itemized");
      expect(ri.value.expense.items).toEqual([
        { id: "li1", name: "Cheese", amountMinor: 600, participantIds: [ana.id] },
        { id: "li2", name: "Wine", amountMinor: 400, participantIds: [ana.id] },
      ]);
    }

    // shares (needs the v11 CHECK widen + shares column) post-migration.
    const rs = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 900 }],
      amountMinor: 900,
      description: "Utilities",
      date: "2026-01-03T00:00:00Z",
      splitType: "shares",
      splits: [{ memberId: ana.id, amountMinor: 900 }],
      shares: [{ memberId: ana.id, weight: 2 }],
    });
    expect(rs.ok).toBe(true);
    if (rs.ok) {
      expect(rs.value.expense.splitType).toBe("shares");
      expect(rs.value.expense.shares).toEqual([{ memberId: ana.id, weight: 2 }]);
    }

    // comments (needs the v12 `comments` table) post-migration.
    if (r.ok) {
      const rc = await g.addComment(r.value.expense.id, ana.id, "Thanks!");
      expect(rc.ok).toBe(true);
      if (rc.ok) {
        expect(rc.value.comment).toMatchObject({
          expenseId: r.value.expense.id, authorMemberId: ana.id, text: "Thanks!",
        });
        expect((await g.listComments(r.value.expense.id)).comments).toEqual([rc.value.comment]);
      }
    }

    // payers (needs the v13 `payers` column) post-migration — only Ana
    // survived the rewind above, so a single-payer write/read round-trip.
    const rp = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 300 }],
      amountMinor: 300,
      description: "Snacks",
      date: "2026-01-04T00:00:00Z",
      splitType: "equal",
      splits: [{ memberId: ana.id, amountMinor: 300 }],
    });
    expect(rp.ok).toBe(true);
    if (rp.ok) {
      expect(rp.value.expense.payers).toEqual([{ memberId: ana.id, amountMinor: 300 }]);
    }

    // tax/tip (needs the v14 `tax_minor`/`tip_minor` columns) post-migration.
    const rt = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 1100 }],
      amountMinor: 1100,
      description: "Dinner",
      date: "2026-01-05T00:00:00Z",
      splitType: "itemized",
      splits: [{ memberId: ana.id, amountMinor: 1100 }],
      items: [{ id: "li3", name: "Curry", amountMinor: 1000, participantIds: [ana.id] }],
      taxMinor: 60,
      tipMinor: 40,
    });
    expect(rt.ok).toBe(true);
    if (rt.ok) {
      expect(rt.value.expense.taxMinor).toBe(60);
      expect(rt.value.expense.tipMinor).toBe(40);
    }
  });

  describe("comments (CHECKLIST.md — Comments on an expense)", () => {
    it("adds, lists (oldest first), and idempotently replays on a repeated id", async () => {
      const g = group("g-comments-ok");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "CMT234");
      const { member: ben } = await g.addMember("Ben");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 500 }], amountMinor: 500, description: "Taxi", date: "2026-01-01T00:00:00Z",
        splitType: "equal", splits: [{ memberId: ana.id, amountMinor: 250 }, { memberId: ben.id, amountMinor: 250 }],
      });
      if (!r.ok) throw new Error("setup failed");
      const expenseId = r.value.expense.id;

      const c1 = await g.addComment(expenseId, ana.id, "I'll cover the tip", "c1");
      const c2 = await g.addComment(expenseId, ben.id, "Thanks!", "c2");
      expect(c1.ok && c2.ok).toBe(true);

      const { comments } = await g.listComments(expenseId);
      expect(comments.map((c) => c.text)).toEqual(["I'll cover the tip", "Thanks!"]);
      expect(comments[0]).toMatchObject({ id: "c1", expenseId, authorMemberId: ana.id });

      // idempotent replay — same id, doesn't insert a second row
      const replay = await g.addComment(expenseId, ana.id, "different text now", "c1");
      expect(replay.ok).toBe(true);
      if (replay.ok) expect(replay.value.comment.text).toBe("I'll cover the tip"); // unchanged
      expect((await g.listComments(expenseId)).comments).toHaveLength(2);
    });

    it("rejects a comment on an expense that doesn't exist", async () => {
      const g = group("g-comments-noexpense");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "CMT235");
      const r = await g.addComment("ghost-expense", ana.id, "hi");
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("NOT_FOUND");
    });

    it("rejects a comment from a member not in the group", async () => {
      const g = group("g-comments-ghost-author");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "CMT236");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T00:00:00Z",
        splitType: "equal", splits: [{ memberId: ana.id, amountMinor: 100 }],
      });
      if (!r.ok) throw new Error("setup failed");
      const c = await g.addComment(r.value.expense.id, "ghost-member", "hi");
      expect(c.ok).toBe(false);
      if (!c.ok) expect(c.error.code).toBe("UNKNOWN_MEMBER");
    });

    it("deleteComment soft-deletes: gone from listComments, idempotent, no restore path", async () => {
      const g = group("g-comments-delete");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "CMT237");
      const r = await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }], amountMinor: 100, description: "x", date: "2026-01-01T00:00:00Z",
        splitType: "equal", splits: [{ memberId: ana.id, amountMinor: 100 }],
      });
      if (!r.ok) throw new Error("setup failed");
      const c = await g.addComment(r.value.expense.id, ana.id, "oops");
      if (!c.ok) throw new Error("setup failed");

      expect(await g.deleteComment(c.value.comment.id, ana.id)).toEqual({ deleted: true });
      expect((await g.listComments(r.value.expense.id)).comments).toEqual([]);
      // idempotent — deleting again is still { deleted: true }, not an error
      expect(await g.deleteComment(c.value.comment.id, ana.id)).toEqual({ deleted: true });
      // deleting an id that never existed is { deleted: false }
      expect(await g.deleteComment("never-existed", ana.id)).toEqual({ deleted: false });
    });
  });

  describe("claim flow", () => {
    it("claimable() lists only placeholders; claim() links one; then it's gone from claimable", async () => {
      const g = group("g-claim");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "CLM234");
      const { member: ben } = await g.addMember("Ben");

      expect((await g.claimable()).members.map((m) => m.displayName)).toEqual(["Ana", "Ben"]);

      const r = await g.claim(ana.id, "apple-sub-ana");
      expect(r.ok).toBe(true);
      if (r.ok) expect(r.value.member).toEqual({ id: ana.id, displayName: "Ana" });

      expect((await g.claimable()).members.map((m) => m.id)).toEqual([ben.id]);
      expect(await g.memberIdentity(ana.id)).toEqual({ sub: "apple-sub-ana" });
      // getState still doesn't expose identity.
      const state = await g.getState();
      expect(state.members).toEqual([
        { id: ana.id, displayName: "Ana" },
        { id: ben.id, displayName: "Ben" },
      ]);
    });

    it("claim() is idempotent for the same sub, rejects a different sub", async () => {
      const g = group("g-claim-idem");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "IDC234");

      const first = await g.claim(ana.id, "sub-1");
      const replay = await g.claim(ana.id, "sub-1");
      expect(first).toEqual(replay);

      const other = await g.claim(ana.id, "sub-2");
      expect(other.ok).toBe(false);
      if (!other.ok) expect(other.error.code).toBe("ALREADY_CLAIMED");
    });

    it("one identity can hold at most one membership per group", async () => {
      const g = group("g-claim-one");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ONE234");
      const { member: ben } = await g.addMember("Ben");

      expect((await g.claim(ana.id, "sub-x")).ok).toBe(true);
      const second = await g.claim(ben.id, "sub-x");
      expect(second.ok).toBe(false);
      if (!second.ok) expect(second.error.code).toBe("IDENTITY_ALREADY_IN_GROUP");
    });

    it("claim() 404s an unknown member", async () => {
      const g = group("g-claim-404");
      await g.initGroup("Trip", "USD", "Ana", "C40234");
      const r = await g.claim("ghost", "sub-y");
      expect(r.ok).toBe(false);
      if (!r.ok) expect(r.error.code).toBe("UNKNOWN_MEMBER");
    });

    it("unclaim() reverts a member to a placeholder, only for its own sub, idempotently", async () => {
      const g = group("g-unclaim");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "UNC234");
      await g.claim(ana.id, "sub-a");

      await g.unclaim(ana.id, "sub-wrong"); // not this identity → no-op
      expect(await g.memberIdentity(ana.id)).toEqual({ sub: "sub-a" });

      await g.unclaim(ana.id, "sub-a");
      expect(await g.memberIdentity(ana.id)).toEqual({ sub: null });
      await g.unclaim(ana.id, "sub-a"); // idempotent
      expect((await g.claimable()).members.map((m) => m.id)).toContain(ana.id);
    });
  });

  describe("claimedRecipientsExcluding (FEATURE_BACKLOG.md — push notifications)", () => {
    it("lists every claimed member except the one excluded, with its memberId, and skips guests", async () => {
      const g = group("g-notify");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "NTF234");
      const { member: ben } = await g.addMember("Ben");
      await g.addMember("Guest"); // never claimed — identity_sub stays null

      await g.claim(ana.id, "apple:ana");
      await g.claim(ben.id, "apple:ben");

      expect(await g.claimedRecipientsExcluding("apple:ana")).toEqual({
        recipients: [{ sub: "apple:ben", memberId: ben.id }],
      });
      expect(await g.claimedRecipientsExcluding("apple:ben")).toEqual({
        recipients: [{ sub: "apple:ana", memberId: ana.id }],
      });
      expect(await g.claimedRecipientsExcluding("apple:someone-else")).toEqual({
        recipients: expect.arrayContaining([
          { sub: "apple:ana", memberId: ana.id },
          { sub: "apple:ben", memberId: ben.id },
        ]),
      });
    });

    it("excludes a member once unclaimed", async () => {
      const g = group("g-notify-unclaim");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "NTU234");
      await g.claim(ana.id, "apple:ana");
      await g.unclaim(ana.id, "apple:ana");

      expect(await g.claimedRecipientsExcluding("apple:someone-else")).toEqual({ recipients: [] });
    });
  });

  it("addExpense returns a failure Result (not a throw) for bad input", async () => {
    const g = group("g-bad");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "BAD234");
    const result = await g.addExpense({
      payers: [{ memberId: ana.id, amountMinor: 100 }],
      amountMinor: 100,
      description: "x",
      date: "2026-01-01T00:00:00Z",
      splitType: "equal",
      splits: [{ memberId: ana.id, amountMinor: 999 }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe("SPLIT_MISMATCH");
  });

  describe("access token (ACCESS_TOKEN_PLAN.md)", () => {
    it("initGroup mints a token, returned from both initGroup and getState", async () => {
      const g = group("g-token-init");
      const { group: created } = await g.initGroup("Trip", "USD", "Ana", "TOK234");
      expect(created.accessToken).toMatch(/^[0-9A-Za-z_-]{22}$/);
      expect(await g.currentAccessToken()).toBe(created.accessToken);

      const state = await g.getState();
      expect(state.group.accessToken).toBe(created.accessToken);
    });

    it("regenerateAccessToken replaces the token", async () => {
      const g = group("g-token-regen");
      const { group: created } = await g.initGroup("Trip", "USD", "Ana", "RGN234");
      const { accessToken: fresh } = await g.regenerateAccessToken();
      expect(fresh).not.toBe(created.accessToken);
      expect(await g.currentAccessToken()).toBe(fresh);
    });

    it("currentAccessToken is null for a group predating this feature, and regenerateAccessToken lazy-mints one", async () => {
      const g = group("g-token-legacy");
      await g.initGroup("Trip", "USD", "Ana", "LEG234");
      // Simulate a group created before ACCESS_TOKEN_PLAN.md shipped — no
      // `access_token` row at all (`initGroup` always writes one now).
      await runInDurableObject(g, (_instance, state) => {
        state.storage.sql.exec("DELETE FROM group_meta WHERE key = 'access_token'");
      });

      expect(await g.currentAccessToken()).toBeNull();
      const state = await g.getState();
      expect(state.group.accessToken).toBeNull();

      const { accessToken: minted } = await g.regenerateAccessToken();
      expect(minted).toMatch(/^[0-9A-Za-z_-]{22}$/);
      expect(await g.currentAccessToken()).toBe(minted);
    });

    it("hasClaimedMember reflects claim() / unclaim()", async () => {
      const g = group("g-token-claimed");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "HCM234");
      expect(await g.hasClaimedMember("sub-a")).toBe(false);

      await g.claim(ana.id, "sub-a");
      expect(await g.hasClaimedMember("sub-a")).toBe(true);
      expect(await g.hasClaimedMember("sub-someone-else")).toBe(false);

      await g.unclaim(ana.id, "sub-a");
      expect(await g.hasClaimedMember("sub-a")).toBe(false);
    });
  });

  describe("trash (FEATURE_BACKLOG.md — delete goes to trash, with attribution)", () => {
    it("deleteExpense soft-deletes: gone from getState/balances, present in trash() with attribution", async () => {
      const g = group("g-trash-expense");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TR1234");
      const { member: ben } = await g.addMember("Ben");
      const { value } = (await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 200 }],
        amountMinor: 200,
        currency: "USD",
        description: "Lunch",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [
          { memberId: ana.id, amountMinor: 100 },
          { memberId: ben.id, amountMinor: 100 },
        ],
      })) as { value: { expense: { id: string } } };

      const del = await g.deleteExpense(value.expense.id, ben.id);
      expect(del).toEqual({ deleted: true });

      const state = await g.getState();
      expect(state.expenses).toEqual([]);
      expect(state.balances).toEqual([]); // the only expense is trashed — nothing owed

      const { expenses } = await g.trash();
      expect(expenses).toHaveLength(1);
      expect(expenses[0]).toMatchObject({ id: value.expense.id, deletedBy: ben.id });
      expect(expenses[0]!.deletedAt).toBeTruthy();
      // Splits survive the soft delete — Restore needs them intact.
      expect(expenses[0]!.splits).toHaveLength(2);
    });

    it("restoreExpense brings it back exactly, clears the trash attribution", async () => {
      const g = group("g-restore-expense");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "RS1234");
      const { value } = (await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }],
        amountMinor: 100,
        currency: "USD",
        description: "Coffee",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 100 }],
      })) as { value: { expense: { id: string } } };
      await g.deleteExpense(value.expense.id, ana.id);

      const restored = await g.restoreExpense(value.expense.id);
      expect(restored.ok).toBe(true);
      if (restored.ok) {
        expect(restored.value.expense).toMatchObject({ id: value.expense.id, description: "Coffee" });
        expect(restored.value.expense.deletedAt).toBeUndefined();
        expect(restored.value.expense.deletedBy).toBeUndefined();
      }

      const state = await g.getState();
      expect(state.expenses).toHaveLength(1);
      expect((await g.trash()).expenses).toEqual([]);
    });

    it("deleteExpense is idempotent both ways: unknown id -> false, already-trashed -> true without overwriting attribution", async () => {
      const g = group("g-trash-idempotent");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "ID1234");
      const { member: ben } = await g.addMember("Ben");
      const { value } = (await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }],
        amountMinor: 100,
        currency: "USD",
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 100 }],
      })) as { value: { expense: { id: string } } };

      expect(await g.deleteExpense("never-existed")).toEqual({ deleted: false });

      await g.deleteExpense(value.expense.id, ana.id);
      expect(await g.deleteExpense(value.expense.id, ben.id)).toEqual({ deleted: true });
      // Second call (attributed to Ben) didn't clobber the original attribution.
      expect((await g.trash()).expenses[0]).toMatchObject({ deletedBy: ana.id });
    });

    it("restoreExpense 404s an unknown id or one that's active, not trashed", async () => {
      const g = group("g-restore-404");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "R41234");
      const { value } = (await g.addExpense({
        payers: [{ memberId: ana.id, amountMinor: 100 }],
        amountMinor: 100,
        currency: "USD",
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ana.id, amountMinor: 100 }],
      })) as { value: { expense: { id: string } } };

      const activeResult = await g.restoreExpense(value.expense.id);
      expect(activeResult.ok).toBe(false);
      if (!activeResult.ok) expect(activeResult.error.code).toBe("NOT_FOUND");

      const ghostResult = await g.restoreExpense("never-existed");
      expect(ghostResult.ok).toBe(false);
    });

    it("deleteSettlement / restoreSettlement mirror the expense behavior", async () => {
      const g = group("g-trash-settlement");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "TS1234");
      const { member: ben } = await g.addMember("Ben");
      const { value } = (await g.addSettlement({
        fromId: ben.id,
        toId: ana.id,
        amountMinor: 300,
        currency: "USD",
      })) as { value: { settlement: { id: string } } };

      await g.deleteSettlement(value.settlement.id, ben.id);
      expect((await g.getState()).settlements).toEqual([]);
      const { settlements } = await g.trash();
      expect(settlements).toMatchObject([{ id: value.settlement.id, deletedBy: ben.id }]);

      const restored = await g.restoreSettlement(value.settlement.id);
      expect(restored.ok).toBe(true);
      expect((await g.getState()).settlements).toHaveLength(1);
      expect((await g.trash()).settlements).toEqual([]);
    });

    it("removeMember isn't blocked by a trashed expense, only an active one", async () => {
      const g = group("g-trash-remove-member");
      const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "RM1234");
      const { member: ben } = await g.addMember("Ben");
      const { value } = (await g.addExpense({
        payers: [{ memberId: ben.id, amountMinor: 100 }],
        amountMinor: 100,
        currency: "USD",
        description: "x",
        date: "2026-01-01T00:00:00Z",
        splitType: "equal",
        splits: [{ memberId: ben.id, amountMinor: 100 }],
      })) as { value: { expense: { id: string } } };

      // While the expense is active, Ben can't be removed.
      const blocked = await g.removeMember(ben.id);
      expect(blocked.ok).toBe(false);

      // Once it's trashed, the reference no longer counts.
      await g.deleteExpense(value.expense.id, ana.id);
      const removed = await g.removeMember(ben.id);
      expect(removed.ok).toBe(true);
    });
  });
});
