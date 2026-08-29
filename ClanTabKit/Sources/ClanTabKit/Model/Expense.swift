import Foundation

/// How an expense's amount was divided among its splits.
public enum SplitType: String, Codable, Sendable {
    case equal
    case exact
}

/// One member's share of an `Expense`. All expense splits for a given expense
/// must sum exactly to that expense's `amountMinor` — see `Validation`.
public struct ExpenseSplit: Codable, Sendable, Equatable {
    public let memberId: String
    public let amountMinor: Int64

    public init(memberId: String, amountMinor: Int64) {
        self.memberId = memberId
        self.amountMinor = amountMinor
    }
}

/// A single payment made by one member on behalf of the group, divided into
/// per-member splits. All amounts are integer minor units (paise/cents) — never
/// floating point, per `AGENTS.md`.
public struct Expense: Identifiable, Codable, Sendable {
    public let id: String
    public let payerId: String
    public let amountMinor: Int64
    public let description: String
    public let date: Date
    public let splitType: SplitType
    public let splits: [ExpenseSplit]

    public init(
        id: String,
        payerId: String,
        amountMinor: Int64,
        description: String,
        date: Date,
        splitType: SplitType,
        splits: [ExpenseSplit]
    ) {
        self.id = id
        self.payerId = payerId
        self.amountMinor = amountMinor
        self.description = description
        self.date = date
        self.splitType = splitType
        self.splits = splits
    }
}
