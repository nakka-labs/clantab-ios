import type { Balance, SimplifiedSettlement } from "./types.ts";

interface Party {
  id: string;
  amount: number;
}

/** Largest amount first; ties broken by `id` ascending — for determinism. */
function sortDescending(items: Party[]): void {
  items.sort((a, b) => (a.amount !== b.amount ? b.amount - a.amount : a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}

/**
 * Greedy debt simplification — a port of `SquareKit`'s `Simplify.simplify`, kept
 * byte-identical by the shared golden fixtures.
 *
 * Repeatedly matches the largest creditor with the largest debtor, settles the
 * smaller of the two amounts between them, and repeats until every balance is
 * zero. Deterministic regardless of input ordering: ties between equal amounts
 * are broken by `memberId`, so the same set of balances always produces the same
 * transaction list (at most N-1 for N members with a nonzero balance).
 */
export function simplify(balances: Balance[]): SimplifiedSettlement[] {
  const creditors: Party[] = [];
  const debtors: Party[] = [];

  for (const b of balances) {
    if (b.netMinor > 0) creditors.push({ id: b.memberId, amount: b.netMinor });
    else if (b.netMinor < 0) debtors.push({ id: b.memberId, amount: -b.netMinor });
  }

  sortDescending(creditors);
  sortDescending(debtors);

  const result: SimplifiedSettlement[] = [];

  while (creditors.length > 0 && debtors.length > 0) {
    const creditor = creditors.shift()!;
    const debtor = debtors.shift()!;

    const amount = Math.min(creditor.amount, debtor.amount);
    result.push({ fromId: debtor.id, toId: creditor.id, amountMinor: amount });

    creditor.amount -= amount;
    debtor.amount -= amount;

    if (creditor.amount > 0) creditors.push(creditor);
    if (debtor.amount > 0) debtors.push(debtor);

    sortDescending(creditors);
    sortDescending(debtors);
  }

  return result;
}
