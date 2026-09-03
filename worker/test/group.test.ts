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
        payerId: ana.id,
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
      payerId: ana.id,
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
      payerId: ana.id,
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
      expect(version).toBe("5");

      // The legacy expense survived the v2 rebuild, gained null category columns,
      // and had its currency backfilled from the group (USD).
      const legacy = sql
        .exec<{ category: string | null; category_icon: string | null; currency: string }>(
          "SELECT category, category_icon, currency FROM expenses WHERE id = 'old-1'",
        )
        .toArray()[0];
      expect(legacy).toEqual({ category: null, category_icon: null, currency: "USD" });

      // The legacy member gained a null identity_sub — i.e. it's a placeholder.
      const member = sql
        .exec<{ identity_sub: string | null }>("SELECT identity_sub FROM members WHERE id = ?", ana.id)
        .toArray()[0];
      expect(member).toEqual({ identity_sub: null });
    });

    // percentage (needs v2), category (needs v3), currency (needs v4) post-migration.
    const r = await g.addExpense({
      payerId: ana.id,
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

  it("addExpense returns a failure Result (not a throw) for bad input", async () => {
    const g = group("g-bad");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "BAD234");
    const result = await g.addExpense({
      payerId: ana.id,
      amountMinor: 100,
      description: "x",
      date: "2026-01-01T00:00:00Z",
      splitType: "equal",
      splits: [{ memberId: ana.id, amountMinor: 999 }],
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error.code).toBe("SPLIT_MISMATCH");
  });
});
