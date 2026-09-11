import type { ExpensePayment, ExpenseSplit, LineItem, ShareWeight } from "./types.ts";

// Money is integer minor units. JavaScript `number` is exact for integers up to
// 2^53; a group's running totals stay many orders of magnitude below that, so
// `number` is safe here as long as every amount is guarded as a positive integer
// on the way in. Reject anything non-integer rather than truncating.

export type ValidationCode =
  | "SPLIT_MISMATCH"
  | "UNKNOWN_MEMBER"
  | "INVALID_AMOUNT"
  // edit / delete: the expense or settlement id in the path doesn't exist
  | "NOT_FOUND"
  // a member can't be removed — it has activity, is claimed, or is the last one
  | "MEMBER_IN_USE"
  // accounts / claim flow (ACCOUNTS_DESIGN.md §6)
  | "ALREADY_CLAIMED"
  | "IDENTITY_ALREADY_IN_GROUP";

/** A validation failure that maps directly to a `DESIGN.md` §2 error envelope. */
export class ValidationFailure extends Error {
  constructor(
    public readonly code: ValidationCode,
    message: string,
  ) {
    super(message);
    this.name = "ValidationFailure";
  }
}

/** Amounts are always positive integers in minor units. */
export function assertPositiveAmount(amountMinor: unknown): asserts amountMinor is number {
  if (typeof amountMinor !== "number" || !Number.isInteger(amountMinor) || amountMinor <= 0) {
    throw new ValidationFailure("INVALID_AMOUNT", "Amount must be a positive integer in minor units.");
  }
}

/**
 * Splits must sum to exactly `amountMinor` — no tolerance. An `equal` split with a
 * remainder is expected to have had that remainder deterministically assigned
 * (client-side, to the payer) before the request is sent, so this is always an
 * exact check (`DESIGN.md` §6). Matches `ClanTabKit`'s `Validation.validateSplitsSum`:
 * only non-empty + exact sum are checked. Individual shares may be `0` (a member
 * included in the expense who owes nothing for it, e.g. `1` minor unit split three
 * ways → `1, 0, 0`); they must be non-negative integers but need not be positive.
 */
export function assertSplitsSum(amountMinor: number, splits: ExpenseSplit[]): void {
  if (splits.length === 0) {
    throw new ValidationFailure("SPLIT_MISMATCH", "An expense must have at least one split.");
  }
  for (const s of splits) {
    if (typeof s.amountMinor !== "number" || !Number.isInteger(s.amountMinor) || s.amountMinor < 0) {
      throw new ValidationFailure("SPLIT_MISMATCH", "Each split amount must be a non-negative integer.");
    }
  }
  const total = splits.reduce((acc, s) => acc + s.amountMinor, 0);
  if (total !== amountMinor) {
    throw new ValidationFailure(
      "SPLIT_MISMATCH",
      `Splits sum to ${total} but the expense amount is ${amountMinor}.`,
    );
  }
}

/**
 * Payers must sum to exactly `amountMinor` — the same integrity rule
 * `assertSplitsSum` already enforces, mirrored for the credit side of an
 * expense (`CHECKLIST.md` "Multiple payers on one expense"). Matches
 * `ClanTabKit`'s `Validation.validatePayersSum`.
 */
export function assertPayersSum(amountMinor: number, payers: ExpensePayment[]): void {
  if (payers.length === 0) {
    throw new ValidationFailure("SPLIT_MISMATCH", "An expense must have at least one payer.");
  }
  for (const p of payers) {
    if (typeof p.amountMinor !== "number" || !Number.isInteger(p.amountMinor) || p.amountMinor <= 0) {
      throw new ValidationFailure("INVALID_AMOUNT", "Each payer's contribution must be a positive integer.");
    }
  }
  const total = payers.reduce((acc, p) => acc + p.amountMinor, 0);
  if (total !== amountMinor) {
    throw new ValidationFailure(
      "SPLIT_MISMATCH",
      `Payers sum to ${total} but the expense amount is ${amountMinor}.`,
    );
  }
}

/** Every referenced member id (payer, split members, settlement from/to) must exist. */
export function assertMembersExist(referencedIds: readonly string[], groupMemberIds: ReadonlySet<string>): void {
  for (const id of referencedIds) {
    if (!groupMemberIds.has(id)) {
      throw new ValidationFailure("UNKNOWN_MEMBER", `Member "${id}" is not in this group.`);
    }
  }
}

/**
 * The line items of an `itemized` expense (`FEATURE_BACKLOG.md` "Itemized
 * expense entry"). At least one item; every item a positive integer amount,
 * shared by at least one real group member; and the item amounts summing to
 * exactly `amountMinor` — there is no separate tax/tip bucket, a shared
 * surcharge is entered as its own line. Mirrors `ClanTabKit.Validation.validateItems`.
 * The resolved `splits` are checked separately by `assertSplitsSum`.
 */
export function assertItemsValid(
  amountMinor: number,
  items: LineItem[],
  groupMemberIds: ReadonlySet<string>,
): void {
  if (items.length === 0) {
    throw new ValidationFailure("SPLIT_MISMATCH", "An itemized expense must have at least one line item.");
  }
  let total = 0;
  for (const item of items) {
    if (typeof item.amountMinor !== "number" || !Number.isInteger(item.amountMinor) || item.amountMinor <= 0) {
      throw new ValidationFailure("INVALID_AMOUNT", "Each line item amount must be a positive integer in minor units.");
    }
    if (item.participantIds.length === 0) {
      throw new ValidationFailure("SPLIT_MISMATCH", `Line item "${item.name}" has no-one sharing it.`);
    }
    assertMembersExist(item.participantIds, groupMemberIds);
    total += item.amountMinor;
  }
  if (total !== amountMinor) {
    throw new ValidationFailure(
      "SPLIT_MISMATCH",
      `Line items sum to ${total} but the expense amount is ${amountMinor}.`,
    );
  }
}

/**
 * The ratio weights of a `shares` expense (`CHECKLIST.md` "Split by shares").
 * At least one weight; every weight a non-negative integer, for a real group
 * member; and a positive total (something to divide by). The weights themselves
 * are arbitrary ratios and are not otherwise constrained. Mirrors
 * `ClanTabKit.Validation.validateShares`. The resolved `splits` are checked
 * separately by `assertSplitsSum`.
 */
export function assertSharesValid(
  shares: ShareWeight[],
  groupMemberIds: ReadonlySet<string>,
): void {
  if (shares.length === 0) {
    throw new ValidationFailure("SPLIT_MISMATCH", "A shares expense must have at least one weight.");
  }
  let total = 0;
  for (const share of shares) {
    if (typeof share.weight !== "number" || !Number.isInteger(share.weight) || share.weight < 0) {
      throw new ValidationFailure("INVALID_AMOUNT", "Each share weight must be a non-negative integer.");
    }
    total += share.weight;
  }
  if (total === 0) {
    throw new ValidationFailure("SPLIT_MISMATCH", "Share weights add up to zero — nothing to divide by.");
  }
  assertMembersExist(shares.map((s) => s.memberId), groupMemberIds);
}
