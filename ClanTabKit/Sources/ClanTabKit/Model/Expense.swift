import Foundation

/// How an expense's amount was divided among its splits.
///
/// `percentage` is a resolved label, not a stored basis: the client turns the
/// entered percentages into exact minor-unit shares (`Validation.percentageSplit`)
/// before dispatch, exactly as `equal` resolves its own remainder, so the split
/// integrity rule (`AGENTS.md`) and the server's exact-sum check are unchanged.
public enum SplitType: String, Codable, Sendable {
    case equal
    case exact
    case percentage
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
    /// Free-form spending category. `nil` for expenses that predate categories or
    /// were left unset — render via `ExpenseCategory.resolve(name:symbolName:)`.
    public let category: String?
    /// The SF Symbol chosen for `category` (`ExpenseCategory.symbolName`). Stored
    /// per expense so any client renders the same icon without a shared table.
    public let categoryIcon: String?

    public init(
        id: String,
        payerId: String,
        amountMinor: Int64,
        description: String,
        date: Date,
        splitType: SplitType,
        splits: [ExpenseSplit],
        category: String? = nil,
        categoryIcon: String? = nil
    ) {
        self.id = id
        self.payerId = payerId
        self.amountMinor = amountMinor
        self.description = description
        self.date = date
        self.splitType = splitType
        self.splits = splits
        self.category = category
        self.categoryIcon = categoryIcon
    }
}
