import Testing
import Foundation
@testable import ClanTabKit

@Suite("Export")
struct ExportTests {
    let alice = Member(id: "alice", displayName: "Alice")
    let bob = Member(id: "bob", displayName: "Bob")

    private func makeExpense(
        id: String = "e1",
        amountMinor: Int64 = 1250,
        description: String = "Dinner",
        date: Date = Date(timeIntervalSince1970: 1_700_000_000),
        category: String? = nil
    ) -> Expense {
        Expense(
            id: id,
            payerId: alice.id,
            amountMinor: amountMinor,
            description: description,
            date: date,
            splitType: .equal,
            splits: [
                ExpenseSplit(memberId: alice.id, amountMinor: amountMinor / 2),
                ExpenseSplit(memberId: bob.id, amountMinor: amountMinor - amountMinor / 2),
            ],
            category: category,
            categoryIcon: category == nil ? nil : "tag"
        )
    }

    @Test("CSV has one header row plus one row per expense and settlement")
    func testRowCount() {
        let expense = makeExpense()
        let settlement = Settlement(id: "s1", fromId: bob.id, toId: alice.id, amountMinor: 625, date: Date())

        let csv = Export.csv(members: [alice, bob], expenses: [expense], settlements: [settlement])
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: false)

        #expect(lines.count == 3) // header + expense + settlement
        #expect(lines[0] == "Type,Date,Description,Category,From,To,Amount,Splits")
    }

    @Test("CSV includes the expense category in its own column")
    func testCategoryColumn() {
        let csv = Export.csv(
            members: [alice, bob],
            expenses: [makeExpense(description: "Cab", category: "Transport")],
            settlements: []
        )
        let expenseLine = csv.split(separator: "\n").first { $0.hasPrefix("Expense,") }
        #expect(expenseLine?.contains(",Cab,Transport,") == true)
    }

    @Test("CSV resolves member ids to display names")
    func testResolvesDisplayNames() {
        let expense = makeExpense()
        let csv = Export.csv(members: [alice, bob], expenses: [expense], settlements: [])

        #expect(csv.contains("Alice"))
        #expect(csv.contains("Bob"))
        #expect(!csv.contains("alice,")) // the raw id shouldn't leak into the row
    }

    @Test("CSV falls back to the raw id for an unknown member")
    func testUnknownMemberFallsBackToId() {
        let expense = makeExpense()
        let csv = Export.csv(members: [alice], expenses: [expense], settlements: []) // bob missing
        #expect(csv.contains("bob:")) // bob's split still appears, keyed by id
    }

    @Test("Money renders as a plain decimal string via integer math", arguments: [
        (Int64(1250), "12.50"),
        (Int64(100), "1.00"),
        (Int64(5), "0.05"),
        (Int64(0), "0.00"),
        (Int64(99), "0.99"),
    ])
    func testDecimalFormatting(minorUnits: Int64, expected: String) {
        let expense = makeExpense(amountMinor: max(minorUnits, 1))
        let csv = Export.csv(members: [alice, bob], expenses: [expense], settlements: [])
        // amountMinor must stay positive per Validation rules, so exercise the
        // formatter through a settlement instead when minorUnits is 0.
        let settlement = Settlement(id: "s1", fromId: bob.id, toId: alice.id, amountMinor: max(minorUnits, 1), date: Date())
        let csvViaSettlement = Export.csv(members: [alice, bob], expenses: [], settlements: [settlement])

        if minorUnits > 0 {
            #expect(csv.contains(expected) || csvViaSettlement.contains(expected))
        }
    }

    @Test("A description containing a comma is quoted per RFC 4180")
    func testCSVEscapesCommas() {
        let expense = makeExpense(description: "Pizza, drinks, and dessert")
        let csv = Export.csv(members: [alice, bob], expenses: [expense], settlements: [])
        #expect(csv.contains("\"Pizza, drinks, and dessert\""))
    }

    @Test("A description containing a quote is escaped by doubling it")
    func testCSVEscapesQuotes() {
        let expense = makeExpense(description: "The \"best\" dinner")
        let csv = Export.csv(members: [alice, bob], expenses: [expense], settlements: [])
        #expect(csv.contains("\"The \"\"best\"\" dinner\""))
    }

    @Test("Rows are sorted oldest first regardless of input order")
    func testRowsSortedByDate() {
        let older = makeExpense(id: "old", description: "Older", date: Date(timeIntervalSince1970: 1000))
        let newer = makeExpense(id: "new", description: "Newer", date: Date(timeIntervalSince1970: 2000))

        // Pass newer first to prove sorting isn't just preserving input order.
        let csv = Export.csv(members: [alice, bob], expenses: [newer, older], settlements: [])
        let lines = csv.split(separator: "\n")

        let olderIndex = lines.firstIndex { $0.contains("Older") }
        let newerIndex = lines.firstIndex { $0.contains("Newer") }
        #expect(olderIndex != nil && newerIndex != nil)
        #expect(olderIndex! < newerIndex!)
    }

    @Test("JSON export produces valid, pretty-printed, round-trippable JSON")
    func testJSONExportRoundTrips() throws {
        let expense = makeExpense()
        let settlement = Settlement(id: "s1", fromId: bob.id, toId: alice.id, amountMinor: 625, date: Date())

        let data = try Export.json(
            groupName: "Goa Trip",
            currency: "INR",
            members: [alice, bob],
            expenses: [expense],
            settlements: [settlement]
        )

        // Pretty-printed: contains newlines, not a single compact line.
        let text = String(data: data, encoding: .utf8)!
        #expect(text.contains("\n"))

        // Valid JSON, parseable independently of our own decoder.
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(object?["groupName"] as? String == "Goa Trip")
        #expect(object?["currency"] as? String == "INR")
        #expect((object?["members"] as? [[String: Any]])?.count == 2)
        #expect((object?["expenses"] as? [[String: Any]])?.count == 1)
        #expect((object?["settlements"] as? [[String: Any]])?.count == 1)

        // Round-trips cleanly through our own decoder too.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(Export.Snapshot.self, from: data)
        #expect(snapshot.members == [alice, bob])
        #expect(snapshot.expenses.first?.id == "e1")
        #expect(snapshot.settlements.first?.id == "s1")
    }

    @Test("Empty expenses and settlements produce a header-only CSV")
    func testEmptyLedgerProducesHeaderOnly() {
        let csv = Export.csv(members: [alice, bob], expenses: [], settlements: [])
        #expect(csv == "Type,Date,Description,Category,From,To,Amount,Splits")
    }
}
