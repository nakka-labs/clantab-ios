import Foundation

/// How an expense's amount was divided among its splits.
///
/// `percentage`, `shares` and `itemized` are resolved labels, not a stored
/// basis: the client turns the entered percentages / ratios / line items into
/// exact minor-unit shares (`Validation.percentageSplit` / `.sharesSplit` /
/// `.itemizedSplit`) before dispatch, exactly as `equal` resolves its own
/// remainder, so the split integrity rule (`AGENTS.md`) and the server's
/// exact-sum check are unchanged. An `itemized` expense also carries its
/// `items`, and a `shares` expense its `shares`, for display / re-edit.
public enum SplitType: String, Codable, Sendable {
    case equal
    case exact
    case percentage
    case itemized
    /// Divide the amount by whole-number ratios (A : 4, B : 2, C : 1 → A pays
    /// 4/7). Same maths as `percentage`; the raw weights are kept in `shares`.
    case shares
}

/// One member's weight in a `shares` split (`CHECKLIST.md` "Split by shares") —
/// a non-negative whole number; a `0` puts the member on the expense owing
/// nothing. The weights are arbitrary ratios and needn't sum to anything.
public struct ShareWeight: Codable, Sendable, Equatable, Identifiable {
    public var id: String { memberId }
    public let memberId: String
    public let weight: Int

    public init(memberId: String, weight: Int) {
        self.memberId = memberId
        self.weight = weight
    }
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

/// One member's contribution toward an `Expense` (`CHECKLIST.md` "Multiple
/// payers on one expense") — every expense has at least one. All of an
/// expense's `payers` must sum exactly to its `amountMinor`, the same
/// integrity rule `splits` already follows — see `Validation`. Same shape as
/// `ExpenseSplit`, kept a distinct type since a payment credits where a split
/// debits (mirrors `ShareWeight` vs. `DefaultSplitWeight`).
public struct ExpensePayment: Codable, Sendable, Equatable {
    public let memberId: String
    public let amountMinor: Int64

    public init(memberId: String, amountMinor: Int64) {
        self.memberId = memberId
        self.amountMinor = amountMinor
    }
}

/// A single payment made by one or more members on behalf of the group, divided
/// into per-member splits. All amounts are integer minor units (paise/cents) —
/// never floating point, per `AGENTS.md`.
public struct Expense: Identifiable, Codable, Sendable {
    public let id: String
    /// Who paid, and how much each contributed — always non-empty, summing
    /// exactly to `amountMinor` (`CHECKLIST.md` "Multiple payers on one
    /// expense"). The overwhelmingly common case is one payer for the whole
    /// amount; use the `init(payerId:...)` convenience for that, or read
    /// `payerId` back for display code that only needs the single-payer case.
    public let payers: [ExpensePayment]
    public let amountMinor: Int64
    /// ISO 4217 code (e.g. "USD"). A group is not restricted to one currency;
    /// ledgers are kept separate per currency and never blended (no FX) — see
    /// `Balances.compute`. `amountMinor` and every split are in this currency.
    public let currency: String
    public let description: String
    public let date: Date
    public let splitType: SplitType
    public let splits: [ExpenseSplit]
    /// The line items an `itemized` expense was built from (`LineItem`) — `nil`
    /// for every other `splitType`. The resolved `splits` stay the source of
    /// truth for balances; `items` is the breakdown that produced them, kept so
    /// reopening the expense shows it and an edit starts from it.
    public let items: [LineItem]?
    /// The whole-number ratios a `shares` expense was built from (`ShareWeight`)
    /// — `nil` for every other `splitType`. Like `items`, the resolved `splits`
    /// stay authoritative for balances; this is kept for display / re-edit.
    public let shares: [ShareWeight]?
    /// Receipt-photo R2 keys (`CHECKLIST.md` "Photo attachment on an expense") —
    /// `nil` (key absent) when the expense has none. Resolve each to a URL with
    /// `ClanTabClient.presignMediaView`.
    public let attachments: [String]?
    /// Free-form spending category. `nil` for expenses that predate categories or
    /// were left unset — render via `ExpenseCategory.resolve(name:symbolName:)`.
    public let category: String?
    /// The SF Symbol chosen for `category` (`ExpenseCategory.symbolName`). Stored
    /// per expense so any client renders the same icon without a shared table.
    public let categoryIcon: String?
    /// Present only in a "Recently Deleted" listing (`FEATURE_BACKLOG.md`) — a
    /// soft-deleted expense is otherwise excluded everywhere else (group
    /// state, balances). `nil` for every expense in the normal ledger.
    public let deletedAt: Date?
    /// The memberId attributed with the delete — client-supplied, trusted at
    /// face value like every other id in this trust model, not
    /// cryptographically verified against a session.
    public let deletedBy: String?

    /// The one payer, when there's exactly one — the overwhelmingly common
    /// case. `nil` for a genuine multi-payer expense; display code that
    /// hasn't been taught to show every payer can fall back to `"Someone"`
    /// or similar, same as an unknown member id anywhere else.
    public var payerId: String? { payers.count == 1 ? payers[0].memberId : nil }

    public init(
        id: String,
        payers: [ExpensePayment],
        amountMinor: Int64,
        currency: String,
        description: String,
        date: Date,
        splitType: SplitType,
        splits: [ExpenseSplit],
        items: [LineItem]? = nil,
        shares: [ShareWeight]? = nil,
        attachments: [String]? = nil,
        category: String? = nil,
        categoryIcon: String? = nil,
        deletedAt: Date? = nil,
        deletedBy: String? = nil
    ) {
        self.id = id
        self.payers = payers
        self.amountMinor = amountMinor
        self.currency = currency
        self.description = description
        self.date = date
        self.splitType = splitType
        self.splits = splits
        self.items = items
        self.shares = shares
        self.attachments = attachments
        self.category = category
        self.categoryIcon = categoryIcon
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
    }

    /// Convenience for the single-payer case, which is most of them — builds
    /// the one-element `payers` array for you. `payer` paid the whole
    /// `amountMinor`.
    public init(
        id: String,
        payerId: String,
        amountMinor: Int64,
        currency: String,
        description: String,
        date: Date,
        splitType: SplitType,
        splits: [ExpenseSplit],
        items: [LineItem]? = nil,
        shares: [ShareWeight]? = nil,
        attachments: [String]? = nil,
        category: String? = nil,
        categoryIcon: String? = nil,
        deletedAt: Date? = nil,
        deletedBy: String? = nil
    ) {
        self.init(
            id: id,
            payers: [ExpensePayment(memberId: payerId, amountMinor: amountMinor)],
            amountMinor: amountMinor,
            currency: currency,
            description: description,
            date: date,
            splitType: splitType,
            splits: splits,
            items: items,
            shares: shares,
            attachments: attachments,
            category: category,
            categoryIcon: categoryIcon,
            deletedAt: deletedAt,
            deletedBy: deletedBy
        )
    }
}
