import SwiftUI
import ClanTabKit

extension ExpenseCategory {
    /// The pastel swatch for this category (`FEATURE_BACKLOG.md` "Category
    /// colors, formula-driven, not hand-picked") — a thin SwiftUI wrapper
    /// around ClanTabKit's pure `CategoryColor.rgb(for:)`.
    var pastelColor: Color {
        let components = CategoryColor.rgb(for: name)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }
}

/// A category's SF Symbol on its own pastel circle — the shared badge used
/// everywhere a category shows up (the activity feed, the category picker).
struct CategoryIconBadge: View {
    let category: ExpenseCategory
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: category.symbolName)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.black.opacity(0.6))
            .frame(width: size, height: size)
            .background(category.pastelColor, in: Circle())
            // Pastel backgrounds are deliberately light in both appearances
            // (`CategoryColor`'s high lightness) — a fixed dark glyph reads
            // correctly on them in dark mode too, unlike `.secondary`.
    }
}
