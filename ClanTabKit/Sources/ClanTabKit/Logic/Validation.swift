import Foundation

/// Errors surfaced by `Validation`. The server-side DO validates independently of the
/// UI — see `DESIGN.md` §6 — so these are the same checks a request handler would run.
public enum ValidationError: Error, Equatable, Sendable {
    case emptySplits
    case splitMismatch(expected: Int64, actual: Int64)
    case unknownMember(String)
    case invalidAmount(Int64)
    /// An itemized expense with no line items.
    case emptyItems
    /// A line item with no-one sharing it.
    case itemWithoutParticipants
    /// The line items don't sum to the expense amount.
    case itemSumMismatch(expected: Int64, actual: Int64)
    /// A `shares` expense with no weights.
    case emptyShares
    /// A share weight is negative, or every weight is `0` (nothing to divide by).
    case invalidShareWeight
    /// An expense with no payers — every expense needs at least one.
    case emptyPayers
    /// The payers' contributions don't sum to the expense amount.
    case payerSumMismatch(expected: Int64, actual: Int64)
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

    /// Verifies that `payers` sum exactly to `amountMinor` (`CHECKLIST.md`
    /// "Multiple payers on one expense") — the same integrity rule
    /// `validateSplitsSum` already enforces, mirrored for the credit side of
    /// an expense rather than the debit side.
    public static func validatePayersSum(amountMinor: Int64, payers: [ExpensePayment]) throws {
        guard !payers.isEmpty else {
            throw ValidationError.emptyPayers
        }
        let total = payers.reduce(Int64(0)) { $0 + $1.amountMinor }
        guard total == amountMinor else {
            throw ValidationError.payerSumMismatch(expected: amountMinor, actual: total)
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

    /// The `shares` counterpart to `percentageSplit` — identical maths (both
    /// divide `amountMinor` by arbitrary non-negative integer weights, leftover
    /// minor units to `remainderRecipient`), named separately only so call sites
    /// read clearly. The weights are raw ratios (4 : 2 : 1), not percentages.
    public static func sharesSplit(
        amountMinor: Int64,
        weights: [(memberId: String, weight: Int)],
        remainderRecipient: String
    ) -> [ExpenseSplit] {
        percentageSplit(amountMinor: amountMinor, weights: weights, remainderRecipient: remainderRecipient)
    }

    /// Checks a `shares` expense's weights: at least one weight, none negative,
    /// a positive total (something to divide by), and every member a real group
    /// member. The weights themselves are unconstrained ratios.
    public static func validateShares(
        weights: [ShareWeight],
        validMemberIds: Set<String>
    ) throws {
        guard !weights.isEmpty else { throw ValidationError.emptyShares }
        guard weights.allSatisfy({ $0.weight >= 0 }) else { throw ValidationError.invalidShareWeight }
        guard weights.reduce(0, { $0 + $1.weight }) > 0 else { throw ValidationError.invalidShareWeight }
        try validateMembersExist(memberIds: weights.map(\.memberId), validMemberIds: validMemberIds)
    }

    /// Resolves an itemized expense (`LineItem`s) into one `ExpenseSplit` per
    /// member who's on at least one item. Each item is divided equally among its
    /// own participants — `equalSplit`'s exact rule, with that item's own
    /// leftover minor unit(s) going to `remainderRecipient` (the payer) when
    /// they're a participant, else the item's first participant — and each
    /// member's shares are then summed across every item.
    ///
    /// If the items sum to `amountMinor` (which `validateItems` enforces before
    /// this is relied on), the returned splits sum to `amountMinor` exactly,
    /// because every item resolves exactly. Members not on any item are omitted
    /// entirely rather than carried at `0` — they simply aren't part of the
    /// expense.
    ///
    /// This is the `itemized` counterpart to `equalSplit` / `percentageSplit`:
    /// the UI works in line items, the wire only ever carries resolved
    /// minor-unit splits (`DESIGN.md` §6).
    public static func itemizedSplit(
        items: [LineItem],
        remainderRecipient: String
    ) -> [ExpenseSplit] {
        var totals: [String: Int64] = [:]
        var order: [String] = []

        for item in items where !item.participantIds.isEmpty {
            let itemSplits = equalSplit(
                amountMinor: item.amountMinor,
                memberIds: item.participantIds,
                remainderRecipient: remainderRecipient
            )
            for split in itemSplits {
                if totals[split.memberId] == nil { order.append(split.memberId) }
                totals[split.memberId, default: 0] += split.amountMinor
            }
        }

        return order.map { ExpenseSplit(memberId: $0, amountMinor: totals[$0] ?? 0) }
    }

    /// Checks an itemized expense's line items: at least one item, every item
    /// shared by at least one member, every participant a real group member, and
    /// the item amounts summing to exactly `amountMinor` (no separate tax/tip
    /// bucket — a shared surcharge is its own line). Individual item amounts must
    /// be positive.
    public static func validateItems(
        amountMinor: Int64,
        items: [LineItem],
        validMemberIds: Set<String>
    ) throws {
        guard !items.isEmpty else { throw ValidationError.emptyItems }

        var total: Int64 = 0
        for item in items {
            guard item.amountMinor > 0 else { throw ValidationError.invalidAmount(item.amountMinor) }
            guard !item.participantIds.isEmpty else { throw ValidationError.itemWithoutParticipants }
            try validateMembersExist(memberIds: item.participantIds, validMemberIds: validMemberIds)
            total += item.amountMinor
        }
        guard total == amountMinor else {
            throw ValidationError.itemSumMismatch(expected: amountMinor, actual: total)
        }
    }
}
