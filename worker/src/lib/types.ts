// Domain types shared by the pure logic modules. These mirror
// `ClanTabKit/Sources/ClanTabKit/Model/` and the wire contract in `DESIGN.md` §2.
// All money is integer minor units (paise/cents) — never floating point.

export interface Member {
  id: string;
  displayName: string;
  /** UPI VPA (e.g. "name@bank"), user-supplied and never verified or
   * processed by ClanTab — `FEATURE_BACKLOG.md` "UPI deep link on Settle
   * Up" builds a plain `upi://pay?...` link from it that hands off to the
   * payer's UPI app; ClanTab itself never sees or moves money. Absent for a
   * member who hasn't set one. */
  upiVpa?: string;
  /** R2 object key for this member's profile photo (`CHECKLIST.md` "Profile
   * photos"), denormalised onto the member row from the linked identity —
   * seeded at claim, kept current by the `PUT`/`DELETE /api/auth/avatar`
   * fan-out. The client resolves it to a URL via `POST /api/media/presign`.
   * Absent for a guest, or a claimed member whose identity has no photo. */
  avatarKey?: string;
}

// `percentage` and `itemized` are resolved labels, not a stored basis — the iOS
// client turns entered percentages / line items into exact minor-unit shares
// before dispatch, exactly as `equal` resolves its own remainder client-side
// (`DESIGN.md` §6). The server still only ever validates that `splits` sum to
// `amountMinor`; for `itemized` it additionally checks `items` are well-formed
// and sum to the amount, and stores them for display / re-edit.
export type SplitType = "equal" | "exact" | "percentage" | "itemized" | "shares";

export interface ExpenseSplit {
  memberId: string;
  amountMinor: number;
}

/** One member's weight in a `shares` split (`CHECKLIST.md` "Split by shares") —
 * mirrors `ClanTabKit.ShareWeight`. Present only on a `shares` expense. A
 * non-negative whole number; the weights are arbitrary ratios (4 : 2 : 1) and
 * needn't sum to anything. */
export interface ShareWeight {
  memberId: string;
  weight: number;
}

/** One line of an itemized expense (`FEATURE_BACKLOG.md` "Itemized expense
 * entry") — mirrors `ClanTabKit.LineItem`. Present only on an `itemized`
 * expense. `participantIds` is never empty; the items together sum to the
 * expense `amountMinor`. */
export interface LineItem {
  id: string;
  name: string;
  amountMinor: number;
  participantIds: string[];
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
  /** The line items an `itemized` expense was built from; absent for every
   * other `splitType`. `splits` stays the source of truth for balances — this
   * is the breakdown that produced them. */
  items?: LineItem[];
  /** The whole-number ratios a `shares` expense was built from; absent for
   * every other `splitType`. `splits` stays the source of truth for balances —
   * this is the breakdown that produced them, kept for re-edit. */
  shares?: ShareWeight[];
  /** R2 object keys for receipt photos (`CHECKLIST.md` "Photo attachment on an
   * expense"), resolved to URLs via `POST /api/media/presign`. Absent when the
   * expense has none. */
  attachments?: string[];
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
