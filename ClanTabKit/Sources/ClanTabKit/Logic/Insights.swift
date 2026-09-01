import Foundation

/// Time bucket size for `Insights.overTime`.
public enum SpendGranularity: String, Sendable, CaseIterable {
    case day, week, month

    var component: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }
}

/// Total group spend for one spending category.
public struct CategorySpend: Equatable, Sendable, Identifiable {
    public let category: ExpenseCategory
    public let totalMinor: Int64
    public var id: String { category.name }

    public init(category: ExpenseCategory, totalMinor: Int64) {
        self.category = category
        self.totalMinor = totalMinor
    }
}

/// One member's share of total group spend — the sum of their split amounts
/// across every expense (what they actually consumed, not what they paid).
public struct MemberSpend: Equatable, Sendable, Identifiable {
    public let member: Member
    public let totalMinor: Int64
    public var id: String { member.id }

    public init(member: Member, totalMinor: Int64) {
        self.member = member
        self.totalMinor = totalMinor
    }
}

/// Group spend within one time bucket. `start` is the first instant of the
/// bucket (start of day / week / month) in the caller's calendar.
public struct SpendBucket: Equatable, Sendable, Identifiable {
    public let start: Date
    public let totalMinor: Int64
    public var id: Date { start }

    public init(start: Date, totalMinor: Int64) {
        self.start = start
        self.totalMinor = totalMinor
    }
}

/// Pure, chart-ready summaries of a group's spending. No I/O, no UI — the App
/// target feeds the results straight into SwiftUI Charts. Settlements are
/// deliberately ignored: they move money between members, they aren't spend.
///
/// Everything is scoped to a single `currency` (spend is never summed across
/// currencies — no FX). Every breakdown sums back to `totalSpend` for that
/// currency, so the three views are consistent.
public enum Insights {
    /// The distinct currencies that appear in `expenses`, in first-appearance
    /// order — for a currency picker on the insights screen.
    public static func currencies(in expenses: [Expense]) -> [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for expense in expenses where seen.insert(expense.currency).inserted {
            order.append(expense.currency)
        }
        return order
    }

    /// Sum of every expense amount in `currency`.
    public static func totalSpend(_ expenses: [Expense], currency: String) -> Int64 {
        expenses.lazy.filter { $0.currency == currency }.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    /// Spend in `currency` grouped by category, largest first. `Uncategorized`
    /// (expenses with no category) is always sorted last regardless of size.
    /// Categories with the same name but different stored icons are merged under
    /// the first icon seen, in expense order.
    public static func byCategory(_ expenses: [Expense], currency: String) -> [CategorySpend] {
        var totals: [String: Int64] = [:]
        var categories: [String: ExpenseCategory] = [:]

        for expense in expenses where expense.currency == currency {
            let category = ExpenseCategory.resolve(name: expense.category, symbolName: expense.categoryIcon)
            totals[category.name, default: 0] += expense.amountMinor
            if categories[category.name] == nil { categories[category.name] = category }
        }

        return totals
            .map { CategorySpend(category: categories[$0.key]!, totalMinor: $0.value) }
            .sorted { lhs, rhs in
                let lhsUncat = lhs.category == .uncategorized
                let rhsUncat = rhs.category == .uncategorized
                if lhsUncat != rhsUncat { return !lhsUncat }
                if lhs.totalMinor != rhs.totalMinor { return lhs.totalMinor > rhs.totalMinor }
                return lhs.category.name < rhs.category.name
            }
    }

    /// Each member's share of `currency` spend (Σ their split amounts), largest
    /// first. Returns exactly one entry per `members` element, so a member who
    /// owes nothing still appears with `0`.
    public static func byMember(_ expenses: [Expense], members: [Member], currency: String) -> [MemberSpend] {
        var totals: [String: Int64] = [:]
        for member in members { totals[member.id] = 0 }
        for expense in expenses where expense.currency == currency {
            for split in expense.splits {
                totals[split.memberId, default: 0] += split.amountMinor
            }
        }

        return members
            .map { MemberSpend(member: $0, totalMinor: totals[$0.id] ?? 0) }
            .sorted { lhs, rhs in
                lhs.totalMinor != rhs.totalMinor
                    ? lhs.totalMinor > rhs.totalMinor
                    : lhs.member.displayName < rhs.member.displayName
            }
    }

    /// Spend in `currency` bucketed over time, oldest first, with empty buckets
    /// between the first and last expense filled in as `0` so a chart doesn't
    /// skip gaps. Returns `[]` when there is no spend in `currency`.
    public static func overTime(
        _ expenses: [Expense],
        currency: String,
        granularity: SpendGranularity,
        calendar: Calendar = .current
    ) -> [SpendBucket] {
        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: granularity.component, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }

        var totals: [Date: Int64] = [:]
        for expense in expenses where expense.currency == currency {
            totals[bucketStart(expense.date), default: 0] += expense.amountMinor
        }

        guard let first = totals.keys.min(), let last = totals.keys.max() else { return [] }

        var buckets: [SpendBucket] = []
        var cursor = first
        while cursor <= last {
            buckets.append(SpendBucket(start: cursor, totalMinor: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: granularity.component, value: 1, to: cursor) else { break }
            cursor = next
        }
        return buckets
    }
}
