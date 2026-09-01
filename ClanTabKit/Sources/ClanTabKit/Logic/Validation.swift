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

    /// Divides `amountMinor` in proportion to integer `weights` (percentages or
    /// shares — any non-negative integers; they need not sum to 100). Each member
    /// gets `floor(amountMinor * weight / totalWeight)`; the leftover minor units
    /// — always fewer than the member count — are assigned to `remainderRecipient`
    /// (normally the payer), falling back to the first member, so the result sums
    /// to exactly `amountMinor`, never gaining or losing a paisa. A `0` weight
    /// yields a `0` share (the member is on the expense but owes nothing for it).
    ///
    /// This is the `percentage` counterpart to `equalSplit`: the UI works in
    /// percentages, the wire only ever carries resolved minor-unit splits.
    public static func percentageSplit(
        amountMinor: Int64,
        weights: [(memberId: String, weight: Int)],
        remainderRecipient: String
    ) -> [ExpenseSplit] {
        precondition(!weights.isEmpty, "Cannot split an expense among zero members")
        let totalWeight = weights.reduce(Int64(0)) { $0 + Int64(max(0, $1.weight)) }
        precondition(totalWeight > 0, "Percentage split needs at least one positive weight")

        var splits = weights.map { entry in
            ExpenseSplit(
                memberId: entry.memberId,
                amountMinor: amountMinor * Int64(max(0, entry.weight)) / totalWeight
            )
        }

        let allocated = splits.reduce(Int64(0)) { $0 + $1.amountMinor }
        let remainder = amountMinor - allocated
        if remainder != 0 {
            let index = splits.firstIndex { $0.memberId == remainderRecipient } ?? 0
            splits[index] = ExpenseSplit(
                memberId: splits[index].memberId,
                amountMinor: splits[index].amountMinor + remainder
            )
        }
        return splits
    }
}
