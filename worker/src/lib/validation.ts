import type { ExpenseSplit } from "./types.ts";

// Money is integer minor units. JavaScript `number` is exact for integers up to
// 2^53; a group's running totals stay many orders of magnitude below that, so
// `number` is safe here as long as every amount is guarded as a positive integer
// on the way in. Reject anything non-integer rather than truncating.

export type ValidationCode =
  | "SPLIT_MISMATCH"
  | "UNKNOWN_MEMBER"
  | "INVALID_AMOUNT"
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

/** Every referenced member id (payer, split members, settlement from/to) must exist. */
export function assertMembersExist(referencedIds: readonly string[], groupMemberIds: ReadonlySet<string>): void {
  for (const id of referencedIds) {
    if (!groupMemberIds.has(id)) {
      throw new ValidationFailure("UNKNOWN_MEMBER", `Member "${id}" is not in this group.`);
    }
  }
}
