import Foundation
import Testing
@testable import ClanTabKit

@Suite("ExpenseCategory")
struct ExpenseCategoryTests {
    @Test("defaults and icon choices are non-empty and use the default symbols")
    func testDefaults() {
        #expect(!ExpenseCategory.defaults.isEmpty)
        for category in ExpenseCategory.defaults {
            #expect(!category.name.isEmpty)
            #expect(ExpenseCategory.iconChoices.contains(category.symbolName))
        }
    }

    @Test("resolve falls back to uncategorized when the name is missing or empty")
    func testResolveFallsBack() {
        #expect(ExpenseCategory.resolve(name: nil, symbolName: "car") == .uncategorized)
        #expect(ExpenseCategory.resolve(name: "", symbolName: "car") == .uncategorized)
    }

    @Test("resolve keeps a stored category, defaulting only the icon")
    func testResolveKeepsStored() {
        #expect(
            ExpenseCategory.resolve(name: "Transport", symbolName: "car")
                == ExpenseCategory(name: "Transport", symbolName: "car")
        )
        let noIcon = ExpenseCategory.resolve(name: "Transport", symbolName: nil)
        #expect(noIcon.name == "Transport")
        #expect(noIcon.symbolName == ExpenseCategory.uncategorized.symbolName)
    }

    @Test("an expense with no category decodes with nil fields")
    func testExpenseDecodesWithoutCategory() throws {
        let json = """
        { "id": "e1", "payerId": "m1", "amountMinor": 100, "currency": "USD", "description": "x",
          "date": "2026-01-01T00:00:00Z", "splitType": "equal",
          "splits": [{ "memberId": "m1", "amountMinor": 100 }] }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let expense = try decoder.decode(Expense.self, from: json)
        #expect(expense.category == nil)
        #expect(expense.categoryIcon == nil)
        #expect(ExpenseCategory.resolve(name: expense.category, symbolName: expense.categoryIcon) == .uncategorized)
    }
}
