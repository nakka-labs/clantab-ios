import Foundation

/// A spending category: a display name plus an SF Symbol.
///
/// Categories are free-form — any name the user types — but the app ships a
/// curated default set (`defaults`) so the common cases are one tap. The symbol
/// is stored on the `Expense` alongside the name (`Expense.categoryIcon`) rather
/// than looked up from a shared name→icon table, so any client can render it
/// without agreeing on a mapping. SF Symbols only, per the portfolio design rule.
public struct ExpenseCategory: Codable, Sendable, Equatable, Hashable {
    public let name: String
    public let symbolName: String

    public init(name: String, symbolName: String) {
        self.name = name
        self.symbolName = symbolName
    }

    /// Shown for an expense with no category — pre-categories expenses, or ones
    /// the user left unset. Never sent on the wire (a nil `category` is the
    /// stored form); this is only the display fallback.
    public static let uncategorized = ExpenseCategory(name: "Uncategorized", symbolName: "tag")

    /// The one-tap options offered at the top of the picker.
    public static let defaults: [ExpenseCategory] = [
        ExpenseCategory(name: "Groceries", symbolName: "cart"),
        ExpenseCategory(name: "Dining", symbolName: "fork.knife"),
        ExpenseCategory(name: "Transport", symbolName: "car"),
        ExpenseCategory(name: "Lodging", symbolName: "bed.double"),
        ExpenseCategory(name: "Entertainment", symbolName: "ticket"),
        ExpenseCategory(name: "Utilities", symbolName: "bolt"),
        ExpenseCategory(name: "Shopping", symbolName: "bag"),
        ExpenseCategory(name: "Health", symbolName: "cross.case"),
        ExpenseCategory(name: "Travel", symbolName: "airplane"),
        ExpenseCategory(name: "Other", symbolName: "square.grid.2x2"),
    ]

    /// SF Symbols offered in the icon grid when naming a custom category — a
    /// superset of the `defaults` symbols.
    public static let iconChoices: [String] = [
        "tag", "cart", "fork.knife", "car", "bed.double", "ticket", "bolt",
        "bag", "cross.case", "airplane", "square.grid.2x2", "house", "gift",
        "wineglass", "cup.and.saucer", "fuelpump", "tram", "bicycle", "pawprint",
        "gamecontroller", "film", "music.note", "book", "graduationcap",
        "wrench.and.screwdriver", "sparkles", "phone", "wifi", "creditcard",
        "banknote", "heart", "figure.run",
    ]

    /// The category for a persisted expense: its stored `name`/`symbolName`, or
    /// `uncategorized` when it predates categories.
    public static func resolve(name: String?, symbolName: String?) -> ExpenseCategory {
        guard let name, !name.isEmpty else { return .uncategorized }
        return ExpenseCategory(name: name, symbolName: symbolName ?? uncategorized.symbolName)
    }
}
