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

  it("getState returns the summary (with joinCode), members oldest-first, and a zero balance", async () => {
    const g = group("g-state");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "XYZ234");
    const { member: ben } = await g.addMember("Ben");

    const state = await g.getState();
    expect(state.group).toMatchObject({ name: "Trip", currency: "USD", joinCode: "XYZ234" });
    expect(state.members.map((m) => m.displayName)).toEqual(["Ana", "Ben"]);
    expect(state.balances).toEqual([
      { memberId: ana.id, netMinor: 0 },
      { memberId: ben.id, netMinor: 0 },
    ]);
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
    expect(state.expenses[0]).toMatchObject({ splitType: "percentage" });
    expect(state.balances).toEqual([
      { memberId: ana.id, netMinor: 400 }, // paid 1000, own share 600
      { memberId: ben.id, netMinor: -400 },
    ]);
  });

  it("migrate() upgrades a v1 expenses table so percentage splits are accepted", async () => {
    const g = group("g-migrate");
    const { member: ana } = await g.initGroup("Trip", "USD", "Ana", "MIG234");
    await g.addMember("Ben");

    // Rewind this DO to the pre-v2 shape: the narrower CHECK and schema_version 1.
    await runInDurableObject(g, (instance, state) => {
      const sql = state.storage.sql;
      sql.exec("DROP TABLE expenses");
      sql.exec(`CREATE TABLE expenses (
        id           TEXT PRIMARY KEY,
        payer_id     TEXT NOT NULL,
        amount_minor INTEGER NOT NULL,
        description  TEXT NOT NULL,
        expense_date TEXT NOT NULL,
        split_type   TEXT NOT NULL CHECK (split_type IN ('equal','exact')),
        created_at   INTEGER NOT NULL
      )`);
      sql.exec("UPDATE group_meta SET value = '1' WHERE key = 'schema_version'");
      (instance as unknown as { migrate(): void }).migrate();

      const version = sql
        .exec<{ value: string }>("SELECT value FROM group_meta WHERE key = 'schema_version'")
        .toArray()[0]?.value;
      expect(version).toBe("2");
    });

    const r = await g.addExpense({
      payerId: ana.id,
      amountMinor: 500,
      description: "Post-migration",
      date: "2026-01-01T00:00:00Z",
      splitType: "percentage",
      splits: [{ memberId: ana.id, amountMinor: 500 }],
    });
    expect(r.ok).toBe(true);
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
