import Foundation

/// One member's share of a group's saved default split, in percent points.
public struct DefaultSplitWeight: Codable, Sendable, Equatable {
    public let memberId: String
    public let weight: Int

    public init(memberId: String, weight: Int) {
        self.memberId = memberId
        self.weight = weight
    }
}

/// A group's saved default split (`FEATURE_BACKLOG.md` "Default split config
/// per group") — percentage weights per member that pre-fill Add Expense's
/// split. `nil` on a group means "split equally among everyone", the app's
/// own default; a stored config is only ever a *percentage* one (an
/// equal-among-everyone default needs no storage).
///
/// A valid config has ≥ 1 member, every weight positive, distinct members,
/// and the weights summing to 100 — the same rule the percentage split UI
/// enforces per expense.
public struct DefaultSplit: Codable, Sendable, Equatable {
    public let weights: [DefaultSplitWeight]

    public init(weights: [DefaultSplitWeight]) {
        self.weights = weights
    }

    public var isValid: Bool {
        !weights.isEmpty
            && weights.allSatisfy { $0.weight > 0 }
            && Set(weights.map(\.memberId)).count == weights.count
            && weights.reduce(0) { $0 + $1.weight } == 100
    }

    /// The config restricted to members still in `members`. `nil` when that
    /// leaves it invalid (a weighted member left, so the remaining weights no
    /// longer sum to 100) — Add Expense should then fall back to an equal
    /// split rather than pre-fill a broken one.
    public func resolved(for members: [Member]) -> DefaultSplit? {
        let ids = Set(members.map(\.id))
        let candidate = DefaultSplit(weights: weights.filter { ids.contains($0.memberId) })
        return candidate.isValid ? candidate : nil
    }
}
