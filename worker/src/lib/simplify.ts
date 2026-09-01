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
 * Greedy debt simplification — a port of `ClanTabKit`'s `Simplify.simplify`, kept
 * byte-identical by the shared golden fixtures.
 *
 * Runs the greedy match **once per currency** (currencies never net against each
 * other — no FX) and concatenates the results in the order the currencies first
 * appear in `balances`. Within a currency: repeatedly match the largest creditor
 * with the largest debtor, settle the smaller amount, repeat. Deterministic
 * regardless of input ordering — ties broken by `memberId`.
 */
export function simplify(balances: Balance[]): SimplifiedSettlement[] {
  const order: string[] = [];
  const byCurrency = new Map<string, Balance[]>();
  for (const b of balances) {
    let group = byCurrency.get(b.currency);
    if (group === undefined) {
      group = [];
      byCurrency.set(b.currency, group);
      order.push(b.currency);
    }
    group.push(b);
  }

  const result: SimplifiedSettlement[] = [];
  for (const currency of order) {
    result.push(...simplifyOneCurrency(byCurrency.get(currency)!, currency));
  }
  return result;
}

function simplifyOneCurrency(balances: Balance[], currency: string): SimplifiedSettlement[] {
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
    result.push({ fromId: debtor.id, toId: creditor.id, amountMinor: amount, currency });

    creditor.amount -= amount;
    debtor.amount -= amount;

    if (creditor.amount > 0) creditors.push(creditor);
    if (debtor.amount > 0) debtors.push(debtor);

    sortDescending(creditors);
    sortDescending(debtors);
  }

  return result;
}
