import Foundation

/// Personal, cross-group spend aggregation for the global Insights tab
/// (`CHECKLIST.md` "Insights tab must show personal data, not a groups
/// list"). Each contribution is one group's expenses plus which member id
/// is "me" *in that group* — member ids are per-group, so a single
/// `Insights.byCategory` call across combined expenses from different
/// groups would silently filter to the wrong (or no) member for every group
/// but one. Instead, each aggregate below runs the existing per-group
/// `Insights` function once per contribution (with that contribution's own
/// correct `myMemberId`) and merges the results. Settlements are ignored,
/// same as `Insights` — they move money between members, they aren't spend.
public enum PersonalInsights {
    public struct GroupContribution: Sendable {
        public let groupId: String
        public let myMemberId: String
        public let expenses: [Expense]

        public init(groupId: String, myMemberId: String, expenses: [Expense]) {
            self.groupId = groupId
            self.myMemberId = myMemberId
            self.expenses = expenses
        }
    }

    /// Every currency appearing in any contribution, first-appearance order
    /// (contributions, then each one's own expenses, in the order given) —
    /// for a currency picker.
    public static func currencies(in contributions: [GroupContribution]) -> [String] {
        var seen: Set<String> = []
        var order: [String] = []
        for contribution in contributions {
            for currency in Insights.currencies(in: contribution.expenses) where seen.insert(currency).inserted {
                order.append(currency)
            }
        }
        return order
    }

    /// My own share of spend in `currency`, summed across every contribution.
    public static func totalSpend(_ contributions: [GroupContribution], currency: String) -> Int64 {
        contributions.reduce(Int64(0)) {
            $0 + Insights.totalSpend($1.expenses, currency: currency, memberId: $1.myMemberId)
        }
    }

    /// My own share of spend in `currency`, by category, summed across every
    /// contribution — same category-merge and sort rule as `Insights
    /// .byCategory` (Uncategorized always last, otherwise largest first).
    public static func byCategory(_ contributions: [GroupContribution], currency: String) -> [CategorySpend] {
        var totals: [String: Int64] = [:]
        var categories: [String: ExpenseCategory] = [:]
        for contribution in contributions {
            for entry in Insights.byCategory(contribution.expenses, currency: currency, memberId: contribution.myMemberId) {
                totals[entry.category.name, default: 0] += entry.totalMinor
                if categories[entry.category.name] == nil { categories[entry.category.name] = entry.category }
            }
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
}
