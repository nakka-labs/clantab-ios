import Foundation
import Testing
@testable import ClanTabKit

@Suite("CSVDuplicateCheck")
struct CSVDuplicateCheckTests {

    private static let day: TimeInterval = 24 * 3600

    private func expense(
        amountMinor: Int64 = 1000, currency: String = "USD", payerId: String = "alex",
        description: String = "Dinner", date: Date = Date(timeIntervalSince1970: 1_000_000),
        deletedAt: Date? = nil
    ) -> Expense {
        Expense(
            id: UUID().uuidString, payerId: payerId, amountMinor: amountMinor, currency: currency,
            description: description, date: date, splitType: .equal,
            splits: [ExpenseSplit(memberId: payerId, amountMinor: amountMinor)],
            deletedAt: deletedAt
        )
    }

    private func settlement(
        amountMinor: Int64 = 1000, currency: String = "USD", fromId: String = "ben", toId: String = "alex",
        date: Date = Date(timeIntervalSince1970: 1_000_000), deletedAt: Date? = nil
    ) -> Settlement {
        Settlement(
            id: UUID().uuidString, fromId: fromId, toId: toId, amountMinor: amountMinor,
            currency: currency, date: date, deletedAt: deletedAt, deletedBy: nil
        )
    }

    // MARK: expenses

    @Test("exact match on every field is a duplicate")
    func testExactMatch() {
        let existing = [expense()]
        #expect(CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a small rounding difference is still a duplicate")
    func testAmountToleranceMatches() {
        let existing = [expense(amountMinor: 1000)]
        #expect(CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1002, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a large amount difference is not a duplicate")
    func testAmountBeyondToleranceDoesNotMatch() {
        let existing = [expense(amountMinor: 1000)]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1500, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a different payer is not a duplicate")
    func testDifferentPayerDoesNotMatch() {
        let existing = [expense(payerId: "alex")]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1000, currency: "USD", payerId: "ben", against: existing
        ))
    }

    @Test("a different currency is not a duplicate even with everything else matching")
    func testDifferentCurrencyDoesNotMatch() {
        let existing = [expense(currency: "USD")]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1000, currency: "EUR", payerId: "alex", against: existing
        ))
    }

    @Test("description match is case- and whitespace-insensitive")
    func testDescriptionMatchIsCaseAndWhitespaceInsensitive() {
        let existing = [expense(description: "  Dinner  ")]
        #expect(CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "DINNER",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a different description is not a duplicate")
    func testDifferentDescriptionDoesNotMatch() {
        let existing = [expense(description: "Dinner")]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Lunch",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a date within the tolerance window still matches")
    func testDateWithinToleranceMatches() {
        let existing = [expense(date: Date(timeIntervalSince1970: 1_000_000))]
        #expect(CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000 + 20 * 3600), description: "Dinner",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a date well outside the tolerance window is not a duplicate")
    func testDateBeyondToleranceDoesNotMatch() {
        let existing = [expense(date: Date(timeIntervalSince1970: 1_000_000))]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000 + 5 * Self.day), description: "Dinner",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("a soft-deleted expense is never a match")
    func testDeletedExpenseIsIgnored() {
        let existing = [expense(deletedAt: Date())]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner",
            amountMinor: 1000, currency: "USD", payerId: "alex", against: existing
        ))
    }

    @Test("the DraftExpense convenience matches the underlying check")
    func testDraftExpenseConvenience() {
        let draft = CSVImport.DraftExpense(
            date: Date(timeIntervalSince1970: 1_000_000), description: "Dinner", amountMinor: 1000,
            currency: "USD", payerName: "Alex", splits: [], category: nil
        )
        let existing = [expense()]
        #expect(CSVDuplicateCheck.isLikelyDuplicate(draft, payerId: "alex", against: existing))
    }

    // MARK: settlements

    @Test("exact match on every field is a duplicate settlement")
    func testSettlementExactMatch() {
        let existing = [settlement()]
        #expect(CSVDuplicateCheck.isLikelyDuplicateSettlement(
            date: Date(timeIntervalSince1970: 1_000_000), fromId: "ben", toId: "alex",
            amountMinor: 1000, currency: "USD", against: existing
        ))
    }

    @Test("swapped from/to is not a duplicate settlement")
    func testSettlementSwappedDirectionDoesNotMatch() {
        let existing = [settlement(fromId: "ben", toId: "alex")]
        #expect(!CSVDuplicateCheck.isLikelyDuplicateSettlement(
            date: Date(timeIntervalSince1970: 1_000_000), fromId: "alex", toId: "ben",
            amountMinor: 1000, currency: "USD", against: existing
        ))
    }

    @Test("the DraftSettlement convenience matches the underlying check")
    func testDraftSettlementConvenience() {
        let draft = CSVImport.DraftSettlement(
            date: Date(timeIntervalSince1970: 1_000_000), fromName: "Ben", toName: "Alex",
            amountMinor: 1000, currency: "USD"
        )
        let existing = [settlement()]
        #expect(CSVDuplicateCheck.isLikelyDuplicate(draft, fromId: "ben", toId: "alex", against: existing))
    }
}
