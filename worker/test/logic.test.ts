import { readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { computeBalances } from "../src/lib/balances.ts";
import { simplify } from "../src/lib/simplify.ts";
import type {
  Balance,
  Expense,
  Member,
  Settlement,
  SimplifiedSettlement,
} from "../src/lib/types.ts";

const fixturesDir = join(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  "test-fixtures",
  "balances",
);

interface Fixture {
  name: string;
  members: Member[];
  expenses: Expense[];
  settlements: Settlement[];
  expectedBalances: Balance[];
  expectedSimplified: SimplifiedSettlement[];
}

const fixtures: Fixture[] = readdirSync(fixturesDir)
  .filter((f) => f.endsWith(".json"))
  .sort()
  .map((f) => JSON.parse(readFileSync(join(fixturesDir, f), "utf8")) as Fixture);

describe("golden fixtures (shared with ClanTabKitTests/GoldenParityTests)", () => {
  it("there are fixtures to run", () => {
    expect(fixtures.length).toBeGreaterThan(0);
  });

  for (const fx of fixtures) {
    it(fx.name, () => {
      const balances = computeBalances(fx.members, fx.expenses, fx.settlements);
      expect(balances).toEqual(fx.expectedBalances);
      expect(simplify(balances)).toEqual(fx.expectedSimplified);
      expect(balances.reduce((sum, b) => sum + b.netMinor, 0)).toBe(0);
    });
  }
});

// --- Deterministic RNG (xorshift128+), so fuzz runs are reproducible ---------

function makeRng(seed: number): () => number {
  let s0 = seed >>> 0 || 1;
  let s1 = (seed * 2654435761) >>> 0 || 2;
  return () => {
    let x = s0;
    const y = s1;
    s0 = y;
    x ^= x << 23;
    x ^= x >>> 17;
    x ^= y ^ (y >>> 26);
    s1 = x >>> 0;
    return ((s0 + s1) >>> 0) / 0x1_0000_0000;
  };
}

function randomZeroSumBalances(memberCount: number, rng: () => number): Balance[] {
  const amounts: number[] = [];
  let running = 0;
  for (let i = 0; i < memberCount - 1; i++) {
    const amount = Math.floor(rng() * 10_001) - 5_000; // [-5000, 5000]
    amounts.push(amount);
    running += amount;
  }
  amounts.push(-running);
  return amounts.map((netMinor, i) => ({ memberId: `member-${i}`, netMinor }));
}

/** Apply a simplified plan on top of balances and check every member lands at zero. */
function planZeroesGroup(original: Balance[], plan: SimplifiedSettlement[]): boolean {
  const net = new Map(original.map((b) => [b.memberId, b.netMinor]));
  for (const t of plan) {
    if (t.amountMinor <= 0) return false;
    net.set(t.fromId, (net.get(t.fromId) ?? 0) + t.amountMinor);
    net.set(t.toId, (net.get(t.toId) ?? 0) - t.amountMinor);
  }
  return [...net.values()].every((v) => v === 0);
}

describe("simplify properties", () => {
  it("is idempotent — running it twice on the same balances gives the same plan", () => {
    for (const fx of fixtures) {
      const balances = computeBalances(fx.members, fx.expenses, fx.settlements);
      expect(simplify(balances)).toEqual(simplify(balances));
    }
  });

  it("seeded fuzz: every plan zeroes the group, uses <= N-1 transactions, and Σpayments == Σpositive", () => {
    const rng = makeRng(0xc0ffee);
    for (let iteration = 0; iteration < 500; iteration++) {
      const memberCount = 2 + Math.floor(rng() * 8); // 2..9
      const balances = randomZeroSumBalances(memberCount, rng);
      const nonZero = balances.filter((b) => b.netMinor !== 0).length;
      const positiveTotal = balances
        .filter((b) => b.netMinor > 0)
        .reduce((s, b) => s + b.netMinor, 0);

      const plan = simplify(balances);

      expect(planZeroesGroup(balances, plan)).toBe(true);
      expect(plan.length).toBeLessThanOrEqual(Math.max(0, nonZero - 1));
      expect(plan.reduce((s, t) => s + t.amountMinor, 0)).toBe(positiveTotal);
    }
  });
});
