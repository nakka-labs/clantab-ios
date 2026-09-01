import Foundation
import Testing
@testable import ClanTabKit

@Suite("Insights")
struct InsightsTests {
    let ana = Member(id: "a", displayName: "Ana")
    let ben = Member(id: "b", displayName: "Ben")
    let cara = Member(id: "c", displayName: "Cara")

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func expense(
        id: String = UUID().uuidString,
        amount: Int64,
        date: Date = Date(timeIntervalSince1970: 0),
        category: String? = nil,
        splits: [ExpenseSplit]
    ) -> Expense {
        Expense(
            id: id, payerId: ana.id, amountMinor: amount, description: "x", date: date,
            splitType: .exact, splits: splits,
            category: category, categoryIcon: category == nil ? nil : "tag"
        )
    }

    @Test("totalSpend sums every expense amount")
    func testTotalSpend() {
        let expenses = [
            expense(amount: 1000, splits: [ExpenseSplit(memberId: ana.id, amountMinor: 1000)]),
            expense(amount: 500, splits: [ExpenseSplit(memberId: ben.id, amountMinor: 500)]),
        ]
        #expect(Insights.totalSpend(expenses) == 1500)
        #expect(Insights.totalSpend([]) == 0)
    }

    @Test("byCategory groups and sorts by total, Uncategorized last")
    func testByCategory() {
        let expenses = [
            expense(amount: 300, category: "Dining", splits: [ExpenseSplit(memberId: ana.id, amountMinor: 300)]),
            expense(amount: 700, category: "Dining", splits: [ExpenseSplit(memberId: ana.id, amountMinor: 700)]),
            expense(amount: 5000, category: nil, splits: [ExpenseSplit(memberId: ana.id, amountMinor: 5000)]),
            expense(amount: 2000, category: "Travel", splits: [ExpenseSplit(memberId: ana.id, amountMinor: 2000)]),
        ]
        let result = Insights.byCategory(expenses)

        #expect(result.map(\.category.name) == ["Travel", "Dining", "Uncategorized"])
        #expect(result.map(\.totalMinor) == [2000, 1000, 5000])
        #expect(result.reduce(Int64(0)) { $0 + $1.totalMinor } == Insights.totalSpend(expenses))
    }

    @Test("byMember returns one entry per member, descending, summing to total")
    func testByMember() {
        let expenses = [
            expense(amount: 1000, splits: [
                ExpenseSplit(memberId: ana.id, amountMinor: 600),
                ExpenseSplit(memberId: ben.id, amountMinor: 400),
            ]),
            expense(amount: 300, splits: [ExpenseSplit(memberId: ben.id, amountMinor: 300)]),
        ]
        let result = Insights.byMember(expenses, members: [ana, ben, cara])

        #expect(result.map(\.member.id) == ["b", "a", "c"]) // 700, 600, 0
        #expect(result.map(\.totalMinor) == [700, 600, 0])
        #expect(result.reduce(Int64(0)) { $0 + $1.totalMinor } == Insights.totalSpend(expenses))
    }

    @Test("overTime buckets by month and fills empty months with zero")
    func testOverTimeMonthlyGapFill() {
        func date(_ iso: String) -> Date {
            let f = ISO8601DateFormatter()
            return f.date(from: iso)!
        }
        let expenses = [
            expense(amount: 100, date: date("2026-01-10T12:00:00Z"), splits: [ExpenseSplit(memberId: ana.id, amountMinor: 100)]),
            expense(amount: 200, date: date("2026-01-20T12:00:00Z"), splits: [ExpenseSplit(memberId: ana.id, amountMinor: 200)]),
            expense(amount: 900, date: date("2026-04-01T12:00:00Z"), splits: [ExpenseSplit(memberId: ana.id, amountMinor: 900)]),
        ]
        let buckets = Insights.overTime(expenses, granularity: .month, calendar: utc)

        #expect(buckets.map(\.totalMinor) == [300, 0, 0, 900]) // Jan, Feb, Mar, Apr
        #expect(buckets.count == 4)
    }

    @Test("overTime is empty for no expenses")
    func testOverTimeEmpty() {
        #expect(Insights.overTime([], granularity: .day, calendar: utc).isEmpty)
    }
}
