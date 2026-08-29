// Domain types shared by the pure logic modules. These mirror
// `ClanTabKit/Sources/ClanTabKit/Model/` and the wire contract in `DESIGN.md` §2.
// All money is integer minor units (paise/cents) — never floating point.

export interface Member {
  id: string;
  displayName: string;
}

export type SplitType = "equal" | "exact";

export interface ExpenseSplit {
  memberId: string;
  amountMinor: number;
}

export interface Expense {
  id: string;
  payerId: string;
  amountMinor: number;
  description: string;
  /** ISO 8601, e.g. "2026-01-01T12:00:00Z". Not used by the balance math. */
  date: string;
  splitType: SplitType;
  splits: ExpenseSplit[];
}

export interface Settlement {
  id: string;
  fromId: string;
  toId: string;
  amountMinor: number;
  date: string;
}

/** Positive = is owed money; negative = owes money. Always derived, never stored. */
export interface Balance {
  memberId: string;
  netMinor: number;
}

export interface SimplifiedSettlement {
  fromId: string;
  toId: string;
  amountMinor: number;
}
