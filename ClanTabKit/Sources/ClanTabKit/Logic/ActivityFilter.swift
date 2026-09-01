import Foundation

/// A category constraint for `ActivityFilter`.
public enum CategoryFilter: Equatable, Hashable, Sendable {
    /// No category constraint.
    case any
    /// Only expenses with no stored category.
    case uncategorized
    /// Only expenses whose `category` equals this name exactly.
    case named(String)
}

/// A user-chosen filter over a group's activity feed. All fields combine with
/// AND; the empty filter (`isActive == false`) matches everything.
///
/// Only the activity feed is filtered — balances and the settle-up plan are
/// always computed over the whole ledger.
public struct ActivityFilter: Equatable, Sendable {
    /// Case- and diacritic-insensitive substring, matched against an expense's
    /// description and the display names of everyone involved (for a settlement,
    /// the two parties).
    public var searchText: String
    /// Restrict to activity involving this member — payer or a split member for
    /// an expense, either party for a settlement.
    public var memberId: String?
    public var category: CategoryFilter

    public init(searchText: String = "", memberId: String? = nil, category: CategoryFilter = .any) {
        self.searchText = searchText
        self.memberId = memberId
        self.category = category
    }

    public var isActive: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || memberId != nil
            || category != .any
    }
}

/// Pure filtering of a group's activity feed. No I/O, no UI.
public enum ActivityFiltering {
    /// Returns the subset of `expenses` and `settlements` matching `filter`, each
    /// in its original order. A category constraint (`.uncategorized` / `.named`)
    /// excludes every settlement, since settlements have no category.
    public static func apply(
        _ filter: ActivityFilter,
        expenses: [Expense],
        settlements: [Settlement],
        members: [Member]
    ) -> (expenses: [Expense], settlements: [Settlement]) {
        guard filter.isActive else { return (expenses, settlements) }

        let names = Dictionary(members.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        let needle = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        func matchesText(_ haystacks: [String]) -> Bool {
            guard !needle.isEmpty else { return true }
            return haystacks.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }

        let filteredExpenses = expenses.filter { expense in
            let involved = [expense.payerId] + expense.splits.map(\.memberId)

            if let memberId = filter.memberId, !involved.contains(memberId) { return false }

            switch filter.category {
            case .any:
                break
            case .uncategorized:
                if let c = expense.category, !c.isEmpty { return false }
            case .named(let name):
                if expense.category != name { return false }
            }

            return matchesText([expense.description] + involved.compactMap { names[$0] })
        }

        let categoryConstrained: Bool = {
            if case .any = filter.category { return false }
            return true
        }()

        let filteredSettlements = categoryConstrained ? [] : settlements.filter { settlement in
            let parties = [settlement.fromId, settlement.toId]
            if let memberId = filter.memberId, !parties.contains(memberId) { return false }
            return matchesText(parties.compactMap { names[$0] })
        }

        return (filteredExpenses, filteredSettlements)
    }

    /// The distinct categories present in `expenses`, sorted by name with
    /// `Uncategorized` last — for populating a category filter menu.
    public static func categories(in expenses: [Expense]) -> [ExpenseCategory] {
        var seen: [String: ExpenseCategory] = [:]
        for expense in expenses {
            let category = ExpenseCategory.resolve(name: expense.category, symbolName: expense.categoryIcon)
            if seen[category.name] == nil { seen[category.name] = category }
        }
        return seen.values.sorted { lhs, rhs in
            let lu = lhs == .uncategorized, ru = rhs == .uncategorized
            if lu != ru { return !lu }
            return lhs.name < rhs.name
        }
    }
}
