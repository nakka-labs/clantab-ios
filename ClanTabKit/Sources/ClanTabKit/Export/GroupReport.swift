import Foundation

/// The data behind the one-page PDF spending report (`FEATURE_BACKLOG.md`
/// "PDF export") — a snapshot gathered from the same `Insights` / `Balances`
/// output every other screen uses. Pure: no I/O, no UI. The App target lays
/// it out with SwiftUI and rasterises it to a PDF.
public struct GroupReportModel: Sendable, Equatable {
    /// One line of the simplified settle-up plan, names and amount resolved.
    public struct SettleLine: Sendable, Equatable, Identifiable {
        public let from: String
        public let to: String
        /// Already formatted, e.g. `"₹500"`.
        public let amount: String
        public var id: String { "\(from)→\(to)-\(amount)" }
    }

    public let groupName: String
    public let emoji: String?
    /// The currency the spend breakdowns are in — the one with the most spend,
    /// falling back to the group's home currency.
    public let currency: String
    public let generatedAt: Date
    /// First and last expense dates, `nil` when there are no expenses.
    public let firstExpenseDate: Date?
    public let lastExpenseDate: Date?
    public let expenseCount: Int
    public let memberCount: Int
    public let totalSpentMinor: Int64
    /// Each member's share of spend in `currency`, largest first.
    public let byMember: [MemberSpend]
    /// Spend by category in `currency`, largest first.
    public let byCategory: [CategorySpend]
    /// The simplified settle-up plan across *every* currency, oldest-debt
    /// order as `Simplify` returns it. Empty = all settled up.
    public let settleUp: [SettleLine]
    /// Currencies with expenses that aren't `currency` — the breakdowns skip
    /// them (spend is never summed across currencies), so the report says so.
    public let otherCurrencies: [String]

    public static func build(from state: GroupStateResponse, now: Date = Date()) -> GroupReportModel {
        let expenses = state.expenses
        let allCurrencies = Insights.currencies(in: expenses)
        let currency = allCurrencies.max { a, b in
            Insights.totalSpend(expenses, currency: a) < Insights.totalSpend(expenses, currency: b)
        } ?? state.group.currency

        let name: (String) -> String = { id in
            state.members.first { $0.id == id }?.displayName ?? "Someone"
        }
        let settleUp = state.simplifiedSettlements.map {
            SettleLine(
                from: name($0.fromId),
                to: name($0.toId),
                amount: MoneyFormat.string(minorUnits: $0.amountMinor, currency: $0.currency)
            )
        }

        return GroupReportModel(
            groupName: state.group.name,
            emoji: state.group.emoji,
            currency: currency,
            generatedAt: now,
            firstExpenseDate: expenses.map(\.date).min(),
            lastExpenseDate: expenses.map(\.date).max(),
            expenseCount: expenses.count,
            memberCount: state.members.count,
            totalSpentMinor: Insights.totalSpend(expenses, currency: currency),
            byMember: Insights.byMember(expenses, members: state.members, currency: currency).filter { $0.totalMinor > 0 },
            byCategory: Insights.byCategory(expenses, currency: currency),
            settleUp: settleUp,
            otherCurrencies: allCurrencies.filter { $0 != currency }
        )
    }
}
