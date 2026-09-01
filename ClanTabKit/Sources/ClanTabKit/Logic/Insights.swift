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
/// Every breakdown here sums back to `totalSpend` (`byMember` because splits
/// always sum to the expense amount, `byCategory` because each expense lands in
/// exactly one bucket), so the three views are consistent.
public enum Insights {
    /// Sum of every expense amount.
    public static func totalSpend(_ expenses: [Expense]) -> Int64 {
        expenses.reduce(Int64(0)) { $0 + $1.amountMinor }
    }

    /// Spend grouped by category, largest first. `Uncategorized` (expenses with
    /// no category) is always sorted last regardless of size. Categories with
    /// the same name but different stored icons are merged under the first icon
    /// seen, in expense order.
    public static func byCategory(_ expenses: [Expense]) -> [CategorySpend] {
        var totals: [String: Int64] = [:]
        var categories: [String: ExpenseCategory] = [:]

        for expense in expenses {
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

    /// Each member's share of total spend (Σ their split amounts), largest
    /// first. Returns exactly one entry per `members` element, so a member who
    /// owes nothing still appears with `0`.
    public static func byMember(_ expenses: [Expense], members: [Member]) -> [MemberSpend] {
        var totals: [String: Int64] = [:]
        for member in members { totals[member.id] = 0 }
        for expense in expenses {
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

    /// Spend bucketed over time, oldest first, with empty buckets between the
    /// first and last expense filled in as `0` so a chart doesn't skip gaps.
    /// Returns `[]` for no expenses.
    public static func overTime(
        _ expenses: [Expense],
        granularity: SpendGranularity,
        calendar: Calendar = .current
    ) -> [SpendBucket] {
        guard !expenses.isEmpty else { return [] }

        func bucketStart(_ date: Date) -> Date {
            calendar.dateInterval(of: granularity.component, for: date)?.start
                ?? calendar.startOfDay(for: date)
        }

        var totals: [Date: Int64] = [:]
        for expense in expenses {
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
