import Foundation
import Testing
@testable import ClanTabKit

@Suite("ActivityFilter")
struct ActivityFilterTests {
    let ana = Member(id: "a", displayName: "Ana")
    let ben = Member(id: "b", displayName: "Ben")
    let cara = Member(id: "c", displayName: "Cára") // diacritic on purpose

    var members: [Member] { [ana, ben, cara] }

    private func expense(
        id: String,
        payer: String,
        description: String,
        splitMembers: [String],
        category: String? = nil
    ) -> Expense {
        Expense(
            id: id, payerId: payer, amountMinor: 300, description: description,
            date: Date(timeIntervalSince1970: 0), splitType: .equal,
            splits: splitMembers.map { ExpenseSplit(memberId: $0, amountMinor: 100) },
            category: category, categoryIcon: category == nil ? nil : "tag"
        )
    }

    private var expenses: [Expense] {
        [
            expense(id: "e1", payer: "a", description: "Groceries run", splitMembers: ["a", "b", "c"], category: "Groceries"),
            expense(id: "e2", payer: "b", description: "Taxi to airport", splitMembers: ["a", "b"], category: "Transport"),
            expense(id: "e3", payer: "c", description: "Random snacks", splitMembers: ["c"], category: nil),
        ]
    }

    private var settlements: [Settlement] {
        [Settlement(id: "s1", fromId: "b", toId: "a", amountMinor: 100, date: Date(timeIntervalSince1970: 0))]
    }

    private func run(_ filter: ActivityFilter) -> (expenses: [String], settlements: [String]) {
        let out = ActivityFiltering.apply(filter, expenses: expenses, settlements: settlements, members: members)
        return (out.expenses.map(\.id), out.settlements.map(\.id))
    }

    @Test("an inactive filter passes everything through unchanged")
    func testInactive() {
        let out = run(ActivityFilter())
        #expect(out.expenses == ["e1", "e2", "e3"])
        #expect(out.settlements == ["s1"])
    }

    @Test("text search matches the description, case- and diacritic-insensitively")
    func testSearchDescription() {
        #expect(run(ActivityFilter(searchText: "TAXI")).expenses == ["e2"])
        #expect(run(ActivityFilter(searchText: "cara")).settlements.isEmpty) // Cára not in s1's parties
    }

    @Test("text search matches an involved member's display name")
    func testSearchMemberName() {
        // "Cára" is on e1 (split) and e3 (payer+split); not on e2; not on s1.
        let out = run(ActivityFilter(searchText: "cara"))
        #expect(out.expenses == ["e1", "e3"])
        #expect(out.settlements.isEmpty)
    }

    @Test("member filter includes payer, split members, and settlement parties")
    func testMemberFilter() {
        let out = run(ActivityFilter(memberId: "a"))
        #expect(out.expenses == ["e1", "e2"]) // not e3 (Cara only)
        #expect(out.settlements == ["s1"])    // Ana is the payee
    }

    @Test("named category filter keeps only that category and drops all settlements")
    func testNamedCategory() {
        let out = run(ActivityFilter(category: .named("Transport")))
        #expect(out.expenses == ["e2"])
        #expect(out.settlements.isEmpty)
    }

    @Test("uncategorized filter matches expenses with no category")
    func testUncategorized() {
        let out = run(ActivityFilter(category: .uncategorized))
        #expect(out.expenses == ["e3"])
        #expect(out.settlements.isEmpty)
    }

    @Test("filters combine with AND")
    func testCombined() {
        let out = run(ActivityFilter(searchText: "run", memberId: "b", category: .named("Groceries")))
        #expect(out.expenses == ["e1"])
    }

    @Test("categories(in:) lists distinct categories, Uncategorized last")
    func testCategoriesList() {
        let names = ActivityFiltering.categories(in: expenses).map(\.name)
        #expect(names == ["Groceries", "Transport", "Uncategorized"])
    }
}
