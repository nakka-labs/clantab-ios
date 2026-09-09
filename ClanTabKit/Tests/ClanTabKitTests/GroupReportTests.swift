import Foundation
import Testing
@testable import ClanTabKit

@Suite("GroupReport")
struct GroupReportTests {
    let ana = Member(id: "a", displayName: "Ana")
    let ben = Member(id: "b", displayName: "Ben")

    private func expense(
        amount: Int64, currency: String = "INR", date: Date = Date(timeIntervalSince1970: 1_000_000),
        category: String? = nil, splits: [ExpenseSplit]
    ) -> Expense {
        Expense(
            id: UUID().uuidString, payerId: ana.id, amountMinor: amount, currency: currency,
            description: "x", date: date, splitType: .exact, splits: splits,
            category: category, categoryIcon: category == nil ? nil : "tag"
        )
    }

    private func state(
        currency: String = "INR",
        emoji: String? = "🏖️",
        expenses: [Expense],
        settlements: [Settlement] = [],
        simplified: [SimplifiedSettlement] = []
    ) -> GroupStateResponse {
        GroupStateResponse(
            group: GroupSummary(name: "Goa Trip", currency: currency, createdAt: .init(timeIntervalSince1970: 0),
                                joinCode: "ABC123", accessToken: nil, emoji: emoji),
            members: [ana, ben], expenses: expenses, settlements: settlements,
            balances: [], simplifiedSettlements: simplified
        )
    }

    @Test("build gathers totals, counts, date range, and breakdowns")
    func testBuild() {
        let d1 = Date(timeIntervalSince1970: 1_000_000)
        let d2 = Date(timeIntervalSince1970: 2_000_000)
        let s = state(expenses: [
            expense(amount: 60000, date: d1, category: "Food",
                    splits: [ExpenseSplit(memberId: ana.id, amountMinor: 30000), ExpenseSplit(memberId: ben.id, amountMinor: 30000)]),
            expense(amount: 40000, date: d2, category: "Travel",
                    splits: [ExpenseSplit(memberId: ana.id, amountMinor: 40000)]),
        ])
        let m = GroupReportModel.build(from: s, now: Date(timeIntervalSince1970: 3_000_000))

        #expect(m.groupName == "Goa Trip")
        #expect(m.emoji == "🏖️")
        #expect(m.currency == "INR")
        #expect(m.totalSpentMinor == 100000)
        #expect(m.expenseCount == 2)
        #expect(m.memberCount == 2)
        #expect(m.firstExpenseDate == d1)
        #expect(m.lastExpenseDate == d2)
        #expect(m.byMember.map(\.member.id) == ["a", "b"]) // Ana 70k, Ben 30k
        #expect(m.byMember.map(\.totalMinor) == [70000, 30000])
        #expect(m.byCategory.map(\.category.name) == ["Food", "Travel"])
        #expect(m.otherCurrencies.isEmpty)
    }

    @Test("settleUp resolves member ids to names and formats the amount")
    func testSettleUp() {
        let s = state(
            expenses: [expense(amount: 20000, splits: [ExpenseSplit(memberId: ben.id, amountMinor: 20000)])],
            simplified: [SimplifiedSettlement(fromId: ben.id, toId: ana.id, amountMinor: 20000, currency: "INR")]
        )
        let m = GroupReportModel.build(from: s)
        #expect(m.settleUp.count == 1)
        #expect(m.settleUp[0].from == "Ben")
        #expect(m.settleUp[0].to == "Ana")
        #expect(m.settleUp[0].amount == "₹200")
    }

    @Test("the report currency is the one with the most spend; the rest are listed as other")
    func testReportCurrencyPicksBiggest() {
        let s = state(currency: "INR", expenses: [
            expense(amount: 10000, currency: "INR", splits: [ExpenseSplit(memberId: ana.id, amountMinor: 10000)]),
            expense(amount: 90000, currency: "USD", splits: [ExpenseSplit(memberId: ana.id, amountMinor: 90000)]),
        ])
        let m = GroupReportModel.build(from: s)
        #expect(m.currency == "USD")
        #expect(m.otherCurrencies == ["INR"])
        #expect(m.totalSpentMinor == 90000)
    }

    @Test("an empty group builds a zeroed report, no crash")
    func testEmpty() {
        let m = GroupReportModel.build(from: state(expenses: []))
        #expect(m.currency == "INR") // falls back to the group's home currency
        #expect(m.totalSpentMinor == 0)
        #expect(m.byMember.isEmpty)
        #expect(m.settleUp.isEmpty)
        #expect(m.firstExpenseDate == nil)
    }
}
