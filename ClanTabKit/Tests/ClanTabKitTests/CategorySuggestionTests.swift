import Foundation
import Testing
@testable import ClanTabKit

@Suite("CategorySuggestion")
struct CategorySuggestionTests {
    @Test("blank description suggests nothing")
    func testBlankSuggestsNothing() {
        #expect(CategorySuggestion.suggest(for: "") == nil)
        #expect(CategorySuggestion.suggest(for: "   ") == nil)
    }

    @Test("no keyword match suggests nothing")
    func testNoMatchSuggestsNothing() {
        #expect(CategorySuggestion.suggest(for: "asdkfjapsdf") == nil)
    }

    @Test("matches common keywords, case-insensitively")
    func testMatchesKnownKeywords() {
        #expect(CategorySuggestion.suggest(for: "Uber to airport")?.name == "Transport")
        #expect(CategorySuggestion.suggest(for: "STARBUCKS")?.name == "Dining")
        #expect(CategorySuggestion.suggest(for: "Costco run")?.name == "Groceries")
        #expect(CategorySuggestion.suggest(for: "Airbnb in Goa")?.name == "Lodging")
        #expect(CategorySuggestion.suggest(for: "Netflix subscription")?.name == "Entertainment")
        #expect(CategorySuggestion.suggest(for: "Electricity bill")?.name == "Utilities")
        #expect(CategorySuggestion.suggest(for: "Amazon order")?.name == "Shopping")
        #expect(CategorySuggestion.suggest(for: "Dentist appointment")?.name == "Health")
        #expect(CategorySuggestion.suggest(for: "Flight to Tokyo")?.name == "Travel")
    }

    @Test("a suggested category's symbol is one of the shared icon choices")
    func testSuggestedSymbolsAreValid() {
        for description in ["Uber", "coffee", "groceries", "hotel", "movie", "rent", "amazon", "pharmacy", "flight"] {
            if let suggestion = CategorySuggestion.suggest(for: description) {
                #expect(ExpenseCategory.iconChoices.contains(suggestion.symbolName))
            }
        }
    }
}
