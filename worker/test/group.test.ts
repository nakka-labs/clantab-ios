import { env } from "cloudflare:test";
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
