// Domain types shared by the pure logic modules. These mirror
// `ClanTabKit/Sources/ClanTabKit/Model/` and the wire contract in `DESIGN.md` §2.
// All money is integer minor units (paise/cents) — never floating point.

export interface Member {
  id: string;
  displayName: string;
}

// `percentage` is a resolved label, not a stored basis — the iOS client turns
// entered percentages into exact minor-unit shares before dispatch, exactly as
// `equal` resolves its own remainder client-side (`DESIGN.md` §6). The server
// still only ever validates that `splits` sum to `amountMinor`.
export type SplitType = "equal" | "exact" | "percentage";

export interface ExpenseSplit {
  memberId: string;
  amountMinor: number;
}

export interface Expense {
  id: string;
  payerId: string;
  amountMinor: number;
  /** ISO 4217 code. Ledgers are kept per-currency and never blended (no FX). */
  currency: string;
  description: string;
  /** ISO 8601, e.g. "2026-01-01T12:00:00Z". Not used by the balance math. */
  date: string;
  splitType: SplitType;
  splits: ExpenseSplit[];
  /** Free-form spending category; absent for expenses that predate categories
   * or were left unset. Not used by the balance math. */
  category?: string;
  /** SF Symbol name chosen for `category` — stored per expense so any client
   * renders the same icon without a shared name→icon table. */
  categoryIcon?: string;
  /** Present only in a "Recently Deleted" listing (`FEATURE_BACKLOG.md`) — a
   * soft-deleted row is otherwise excluded from every response entirely
   * (`getState`, balances, `addExpense` replay). ISO 8601, seconds precision. */
  deletedAt?: string;
  /** The memberId attributed with the delete — client-supplied, trusted at
   * face value like every other identifier in this trust model (`DESIGN.md`
   * §6/§8); not cryptographically verified against a session. */
  deletedBy?: string;
}

export interface Settlement {
  id: string;
  fromId: string;
  toId: string;
  amountMinor: number;
  currency: string;
  date: string;
  /** See `Expense.deletedAt`/`deletedBy` — same "Recently Deleted"-only shape. */
  deletedAt?: string;
  deletedBy?: string;
}

/**
 * A member's net position in one currency — positive = is owed, negative = owes.
 * Always derived, never stored. A member active in N currencies has N `Balance`
 * entries; currencies are never blended.
 */
export interface Balance {
  memberId: string;
  currency: string;
  netMinor: number;
}

export interface SimplifiedSettlement {
  fromId: string;
  toId: string;
  amountMinor: number;
  currency: string;
}
