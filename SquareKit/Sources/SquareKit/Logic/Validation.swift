import Foundation

/// Errors surfaced by `Validation`. The server-side DO validates independently of the
/// UI — see `DESIGN.md` §6 — so these are the same checks a request handler would run.
public enum ValidationError: Error, Equatable, Sendable {
    case emptySplits
    case splitMismatch(expected: Int64, actual: Int64)
    case unknownMember(String)
    case invalidAmount(Int64)
}

/// Split-sum validation and deterministic remainder distribution.
public enum Validation {
    /// Verifies that `splits` sum exactly to `amountMinor`. No tolerance: an equal
    /// split with a remainder must already have that remainder deterministically
    /// assigned (see `equalSplit`) before this is called.
    public static func validateSplitsSum(amountMinor: Int64, splits: [ExpenseSplit]) throws {
        guard !splits.isEmpty else {
            throw ValidationError.emptySplits
        }
        let total = splits.reduce(Int64(0)) { $0 + $1.amountMinor }
        guard total == amountMinor else {
            throw ValidationError.splitMismatch(expected: amountMinor, actual: total)
        }
    }

    /// Verifies every referenced member id (payer, split members, settlement
    /// from/to) actually belongs to the group.
    public static func validateMembersExist(memberIds: [String], validMemberIds: Set<String>) throws {
        for id in memberIds {
            guard validMemberIds.contains(id) else {
                throw ValidationError.unknownMember(id)
            }
        }
    }

    /// Amounts are always positive integers in minor units.
    public static func validatePositiveAmount(_ amountMinor: Int64) throws {
        guard amountMinor > 0 else {
            throw ValidationError.invalidAmount(amountMinor)
        }
    }

    /// Divides `amountMinor` evenly across `memberIds`, assigning the integer-division
    /// remainder to `remainderRecipient` (normally the payer) so the result always sums
    /// to exactly `amountMinor` — never gaining or losing a paisa. Falls back to the
    /// first member if `remainderRecipient` isn't among `memberIds`, so the sum
    /// invariant holds unconditionally.
    public static func equalSplit(
        amountMinor: Int64,
        memberIds: [String],
        remainderRecipient: String
    ) -> [ExpenseSplit] {
        precondition(!memberIds.isEmpty, "Cannot split an expense among zero members")

        let count = Int64(memberIds.count)
        let base = amountMinor / count
        let remainder = amountMinor % count
        let recipient = memberIds.contains(remainderRecipient) ? remainderRecipient : memberIds[0]

        return memberIds.map { id in
            ExpenseSplit(memberId: id, amountMinor: id == recipient ? base + remainder : base)
        }
    }
}
