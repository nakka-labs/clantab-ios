import type { Balance, Expense, Member, Settlement } from "./types.ts";

/**
 * Pure derivation of member balances from a group's full event history — a port of
 * `ClanTabKit`'s `Balances.compute`, kept byte-identical by the shared golden
 * fixtures in `test-fixtures/balances/` (run by both this suite and
 * `ClanTabKitTests`).
 *
 * For every expense the payer is credited the full `amountMinor` and every split
 * member (possibly including the payer) is debited their share. For every
 * settlement `fromId` is credited and `toId` is debited. Returns exactly one
 * `Balance` per `members` entry, in the same order; the result always sums to zero.
 */
export function computeBalances(
  members: Member[],
  expenses: Expense[],
  settlements: Settlement[],
): Balance[] {
  const net = new Map<string, number>();
  for (const m of members) net.set(m.id, 0);

  const add = (id: string, delta: number): void => {
    net.set(id, (net.get(id) ?? 0) + delta);
  };

  for (const e of expenses) {
    add(e.payerId, e.amountMinor);
    for (const s of e.splits) add(s.memberId, -s.amountMinor);
  }

  for (const s of settlements) {
    add(s.fromId, s.amountMinor);
    add(s.toId, -s.amountMinor);
  }

  return members.map((m) => ({ memberId: m.id, netMinor: net.get(m.id) ?? 0 }));
}
