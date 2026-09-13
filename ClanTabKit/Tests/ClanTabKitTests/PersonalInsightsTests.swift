import Foundation
import Testing
@testable import ClanTabKit

@Suite("PersonalInsights")
struct PersonalInsightsTests {
    // Two different groups, each with its own member-id space — "me" is
    // "a" in group 1 but "x" in group 2, deliberately colliding with group
    // 1's member ids nowhere, to catch a cross-group id mixup.
    private func expense(
        payer: String, amount: Int64, currency: String = "USD",
        category: String? = nil, splits: [ExpenseSplit]
    ) -> Expense {
        Expense(
            id: UUID().uuidString, payerId: payer, amountMinor: amount, currency: currency,
            description: "x", date: Date(timeIntervalSince1970: 0), splitType: .exact, splits: splits,
            category: category, categoryIcon: category == nil ? nil : "tag"
        )
    }

    @Test("totalSpend sums my own share across groups, each using its own member id")
    func testTotalSpend() {
        let group1 = PersonalInsights.GroupContribution(
            groupId: "g1", myMemberId: "a",
            expenses: [expense(payer: "a", amount: 1000, splits: [
                ExpenseSplit(memberId: "a", amountMinor: 600), ExpenseSplit(memberId: "b", amountMinor: 400),
            ])]
        )
        let group2 = PersonalInsights.GroupContribution(
            groupId: "g2", myMemberId: "x",
            expenses: [expense(payer: "y", amount: 500, splits: [
                ExpenseSplit(memberId: "x", amountMinor: 200), ExpenseSplit(memberId: "y", amountMinor: 300),
            ])]
        )
        #expect(PersonalInsights.totalSpend([group1, group2], currency: "USD") == 800) // 600 + 200
    }

    @Test("byCategory merges each group's own byCategory result by category name")
    func testByCategory() {
        let group1 = PersonalInsights.GroupContribution(
            groupId: "g1", myMemberId: "a",
            expenses: [expense(payer: "a", amount: 1000, category: "Dining", splits: [
                ExpenseSplit(memberId: "a", amountMinor: 700), ExpenseSplit(memberId: "b", amountMinor: 300),
            ])]
        )
        let group2 = PersonalInsights.GroupContribution(
            groupId: "g2", myMemberId: "x",
            expenses: [
                expense(payer: "x", amount: 400, category: "Dining", splits: [
                    ExpenseSplit(memberId: "x", amountMinor: 400),
                ]),
                expense(payer: "x", amount: 900, category: "Travel", splits: [
                    ExpenseSplit(memberId: "x", amountMinor: 900),
                ]),
            ]
        )
        let result = PersonalInsights.byCategory([group1, group2], currency: "USD")
        // Dining: 700 (g1) + 400 (g2) = 1100, ahead of Travel's 900.
        #expect(result.map(\.category.name) == ["Dining", "Travel"])
        #expect(result.map(\.totalMinor) == [1100, 900])
    }

    @Test("a currency only present in one group's contribution isn't blended with another")
    func testCurrencyIsolation() {
        let inr = PersonalInsights.GroupContribution(
            groupId: "g1", myMemberId: "a",
            expenses: [expense(payer: "a", amount: 1000, currency: "INR", splits: [
                ExpenseSplit(memberId: "a", amountMinor: 1000),
            ])]
        )
        let usd = PersonalInsights.GroupContribution(
            groupId: "g2", myMemberId: "x",
            expenses: [expense(payer: "x", amount: 50, currency: "USD", splits: [
                ExpenseSplit(memberId: "x", amountMinor: 50),
            ])]
        )
        #expect(PersonalInsights.totalSpend([inr, usd], currency: "INR") == 1000)
        #expect(PersonalInsights.totalSpend([inr, usd], currency: "USD") == 50)
        #expect(Set(PersonalInsights.currencies(in: [inr, usd])) == ["INR", "USD"])
    }

    @Test("empty contributions yield nothing")
    func testEmpty() {
        #expect(PersonalInsights.totalSpend([], currency: "USD") == 0)
        #expect(PersonalInsights.byCategory([], currency: "USD").isEmpty)
        #expect(PersonalInsights.currencies(in: []).isEmpty)
    }
}
