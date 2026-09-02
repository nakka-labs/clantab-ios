import Foundation
import Testing
@testable import ClanTabKit

@Suite("CSVImport")
struct CSVImportTests {

    // MARK: tokenizer

    @Test("tokenizer handles quoted commas, doubled quotes, and quoted newlines")
    func testTokenizer() {
        let csv = "a,b,c\n\"x,y\",\"he said \"\"hi\"\"\",\"two\nlines\"\n"
        let rows = CSVImport.tokenize(csv)
        #expect(rows[0] == ["a", "b", "c"])
        #expect(rows[1] == ["x,y", "he said \"hi\"", "two\nlines"])
    }

    // MARK: amount parsing

    @Test("parseSignedAmount", arguments: [
        ("12", Int64(1200)), ("12.5", Int64(1250)), ("12.50", Int64(1250)),
        ("0.05", Int64(5)), ("1,234.00", Int64(123_400)), ("-20.00", Int64(-2000)),
    ])
    func testParseAmount(input: String, expected: Int64) {
        #expect(CSVImport.parseSignedAmount(input) == expected)
    }

    @Test("parseAmount rejects negatives and junk")
    func testParseAmountRejects() {
        #expect(CSVImport.parseAmount("-1.00") == nil)
        #expect(CSVImport.parseAmount("abc") == nil)
        #expect(CSVImport.parseAmount("") == nil)
    }

    // MARK: format detection

    @Test("an unrecognised header throws")
    func testUnrecognised() {
        #expect(throws: CSVImport.ParseError.unrecognizedFormat) {
            try CSVImport.parse("foo,bar\n1,2\n")
        }
    }

    // MARK: ClanTab format

    private let clanTabCSV = """
    Type,Date,Description,Category,From,To,Amount,Currency,Splits
    Expense,2026-07-01T12:00:00Z,"Lunch, drinks",Dining,Ana,,30.00,USD,Ana:15.00; Ben:15.00
    Settlement,2026-07-02T09:00:00Z,,,Ben,Ana,15.00,USD,
    """

    @Test("parses the ClanTab export format")
    func testClanTab() throws {
        let r = try CSVImport.parse(clanTabCSV)
        #expect(r.format == .clanTab)
        #expect(r.referencedNames == ["Ana", "Ben"])

        #expect(r.expenses.count == 1)
        let e = r.expenses[0]
        #expect(e.description == "Lunch, drinks")
        #expect(e.amountMinor == 3000)
        #expect(e.currency == "USD")
        #expect(e.payerName == "Ana")
        #expect(e.category == "Dining")
        #expect(e.splits == [
            CSVImport.DraftSplit(memberName: "Ana", amountMinor: 1500),
            CSVImport.DraftSplit(memberName: "Ben", amountMinor: 1500),
        ])

        #expect(r.settlements.count == 1)
        let s = r.settlements[0]
        #expect(s.fromName == "Ben")
        #expect(s.toName == "Ana")
        #expect(s.amountMinor == 1500)
        #expect(s.date == ISO8601DateFormatter().date(from: "2026-07-02T09:00:00Z"))
    }

    @Test("ClanTab rows whose splits don't add up are skipped with a warning")
    func testClanTabBadSplits() throws {
        let csv = """
        Type,Date,Description,Category,From,To,Amount,Currency,Splits
        Expense,2026-07-01T12:00:00Z,X,,Ana,,30.00,USD,Ana:10.00; Ben:5.00
        Expense,2026-07-02T12:00:00Z,Y,,Ana,,10.00,USD,Ana:10.00
        """
        let r = try CSVImport.parse(csv)
        #expect(r.expenses.map(\.description) == ["Y"])
        #expect(r.warnings.count == 1)
    }

    @Test("Export.csv round-trips through CSVImport.parse")
    func testRoundTrip() throws {
        let ana = Member(id: "a", displayName: "Ana")
        let ben = Member(id: "b", displayName: "Ben")
        let expense = Expense(
            id: "e1", payerId: "a", amountMinor: 2500, currency: "EUR", description: "Taxi",
            date: Date(timeIntervalSince1970: 1_700_000_000), splitType: .exact,
            splits: [ExpenseSplit(memberId: "a", amountMinor: 1000), ExpenseSplit(memberId: "b", amountMinor: 1500)],
            category: "Transport", categoryIcon: "car"
        )
        let settlement = Settlement(
            id: "s1", fromId: "b", toId: "a", amountMinor: 500, currency: "EUR",
            date: Date(timeIntervalSince1970: 1_700_100_000)
        )

        let csv = Export.csv(members: [ana, ben], expenses: [expense], settlements: [settlement])
        let r = try CSVImport.parse(csv)

        #expect(r.expenses.count == 1)
        let e = r.expenses[0]
        #expect(e.payerName == "Ana")
        #expect(e.amountMinor == 2500)
        #expect(e.currency == "EUR")
        #expect(e.category == "Transport")
        #expect(Set(e.splits) == [
            CSVImport.DraftSplit(memberName: "Ana", amountMinor: 1000),
            CSVImport.DraftSplit(memberName: "Ben", amountMinor: 1500),
        ])
        #expect(r.settlements.first?.amountMinor == 500)
        #expect(r.settlements.first?.fromName == "Ben")
    }

    // MARK: Splitwise format

    @Test("reconstructs a single-payer expense from the Splitwise format")
    func testSplitwiseSinglePayer() throws {
        // Ana paid 60, split equally 3 ways (20 each). Net: Ana +40, Ben −20, Cal −20.
        let csv = """
        Date,Description,Category,Cost,Currency,Ana,Ben,Cal
        2026-07-01,Groceries,General,60.00,USD,40.00,-20.00,-20.00
        2026-07-02,Hotel,Travel,120.00,USD,-60.00,90.00,-30.00
        Total balance,,,,,20.00,10.00,-30.00
        """
        let r = try CSVImport.parse(csv)
        #expect(r.format == .splitwise)
        #expect(r.settlements.isEmpty)
        #expect(r.expenses.count == 2)

        let groceries = r.expenses[0]
        #expect(groceries.payerName == "Ana")
        #expect(groceries.amountMinor == 6000)
        #expect(groceries.category == nil) // "General" → nil
        #expect(Set(groceries.splits) == [
            CSVImport.DraftSplit(memberName: "Ana", amountMinor: 2000),
            CSVImport.DraftSplit(memberName: "Ben", amountMinor: 2000),
            CSVImport.DraftSplit(memberName: "Cal", amountMinor: 2000),
        ])

        let hotel = r.expenses[1]
        #expect(hotel.payerName == "Ben") // largest net (+90)
        #expect(hotel.category == "Travel")
        #expect(hotel.splits.reduce(Int64(0)) { $0 + $1.amountMinor } == 12000)
    }

    @Test("a genuine multi-payer Splitwise row is skipped with a warning")
    func testSplitwiseMultiPayerSkipped() throws {
        // Ana +10, Ben +10, Cal −20: two people are net-positive → a non-payer
        // share comes out negative, which Splitwise can't represent losslessly.
        let csv = """
        Date,Description,Category,Cost,Currency,Ana,Ben,Cal
        2026-07-01,Split cab,General,20.00,USD,10.00,10.00,-20.00
        """
        let r = try CSVImport.parse(csv)
        #expect(r.expenses.isEmpty)
        #expect(r.warnings.count == 1)
        #expect(r.warnings[0].contains("multi-payer"))
    }
}
