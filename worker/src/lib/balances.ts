import type { Balance, Expense, Member, Settlement } from "./types.ts";

/**
 * Pure derivation of member balances from a group's full event history,
 * **partitioned by currency** — a port of `ClanTabKit`'s `Balances.compute`, kept
 * byte-identical by the shared golden fixtures in `test-fixtures/balances/` (run
 * by both this suite and `ClanTabKitTests`).
 *
 * Within each currency bucket: the payer is credited the full `amountMinor` and
 * every split member is debited their share; for a settlement `fromId` is
 * credited and `toId` debited. Returns one `Balance` per (member, currency) that
 * nets to a nonzero amount, ordered by currency (first-appearance order across
 * the combined expense-then-settlement stream) then by `members` order. Every
 * currency bucket sums to zero; no activity yields `[]`.
 */
export function computeBalances(
  members: Member[],
  expenses: Expense[],
  settlements: Settlement[],
): Balance[] {
  const byCurrency = new Map<string, Map<string, number>>();

  const bucket = (currency: string): Map<string, number> => {
    let nets = byCurrency.get(currency);
    if (nets === undefined) {
      nets = new Map<string, number>();
      byCurrency.set(currency, nets);
    }
    return nets;
  };

  const add = (nets: Map<string, number>, id: string, delta: number): void => {
    nets.set(id, (nets.get(id) ?? 0) + delta);
  };

  for (const e of expenses) {
    const nets = bucket(e.currency);
    add(nets, e.payerId, e.amountMinor);
    for (const s of e.splits) add(nets, s.memberId, -s.amountMinor);
  }

  for (const s of settlements) {
    const nets = bucket(s.currency);
    add(nets, s.fromId, s.amountMinor);
    add(nets, s.toId, -s.amountMinor);
  }

  const result: Balance[] = [];
  for (const [currency, nets] of byCurrency) {
    for (const m of members) {
      const net = nets.get(m.id) ?? 0;
      if (net !== 0) result.push({ memberId: m.id, currency, netMinor: net });
    }
  }
  return result;
}
