import Foundation

/// Guesses a spending category from an expense's free-text description
/// (`CHECKLIST.md` "Friend playtest, round 3" — "automatic smart category
/// suggestions based on expense name/description"). A plain keyword
/// heuristic, not a model: no backend/LLM infrastructure exists in this app
/// (a stateless Worker + fully offline-capable client), and a contained
/// client-side lookup is enough to save the common one-tap case without
/// pulling in a dependency for it.
///
/// Deliberately narrow — a *suggestion*, never forced: callers only apply it
/// while the category is still unset, so it can't fight a category the user
/// (or an import, or a duplicate) already set.
public enum CategorySuggestion {
    /// Checked in order, first match wins — so a more specific keyword
    /// listed earlier (e.g. "pizza" under Dining) beats an accidental
    /// overlap with a later, broader one. Each keyword is matched as a
    /// case-insensitive substring, not a whole-word match, since a
    /// description is rarely more than a couple of words ("Uber to
    /// airport", "Costco run").
    private static let rules: [(keywords: [String], category: ExpenseCategory)] = [
        (
            ["uber", "lyft", "taxi", "cab", "gas", "petrol", "fuel", "parking", "metro", "subway", "train", "bus fare", "toll"],
            ExpenseCategory(name: "Transport", symbolName: "car")
        ),
        (
            ["restaurant", "cafe", "coffee", "starbucks", "lunch", "dinner", "breakfast", "brunch", "pizza", "diner", "takeout", "food"],
            ExpenseCategory(name: "Dining", symbolName: "fork.knife")
        ),
        (
            ["grocery", "groceries", "supermarket", "market", "walmart", "costco", "whole foods", "trader joe"],
            ExpenseCategory(name: "Groceries", symbolName: "cart")
        ),
        (
            ["hotel", "airbnb", "motel", "resort", "lodging", "hostel"],
            ExpenseCategory(name: "Lodging", symbolName: "bed.double")
        ),
        (
            ["movie", "cinema", "concert", "netflix", "spotify", "theater", "theatre", "show", "museum", "game night"],
            ExpenseCategory(name: "Entertainment", symbolName: "ticket")
        ),
        (
            ["electricity", "water bill", "utility", "utilities", "internet bill", "wifi bill", "phone bill", "rent"],
            ExpenseCategory(name: "Utilities", symbolName: "bolt")
        ),
        (
            ["amazon", "mall", "clothes", "clothing", "shoes", "shopping"],
            ExpenseCategory(name: "Shopping", symbolName: "bag")
        ),
        (
            ["pharmacy", "doctor", "hospital", "medicine", "medical", "clinic", "dentist"],
            ExpenseCategory(name: "Health", symbolName: "cross.case")
        ),
        (
            ["flight", "airline", "airport", "visa", "vacation"],
            ExpenseCategory(name: "Travel", symbolName: "airplane")
        ),
    ]

    /// The best-guess category for `description`, or `nil` for a blank
    /// description or no keyword match.
    public static func suggest(for description: String) -> ExpenseCategory? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty else { return nil }
        for rule in rules where rule.keywords.contains(where: { text.contains($0) }) {
            return rule.category
        }
        return nil
    }
}
