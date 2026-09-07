import SwiftUI
import ClanTabKit

extension MemberColor {
    /// The member's identity swatch as a SwiftUI `Color` — a thin wrapper
    /// around ClanTabKit's pure `MemberColor.rgb(for:)` (same split as
    /// `ExpenseCategory.pastelColor`).
    static func color(for displayName: String) -> Color {
        let c = rgb(for: displayName)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}

/// A member's initials on their formula-driven identity circle
/// (`CHECKLIST.md` "Member identity color/avatar") — the shared avatar used
/// everywhere a member shows up: the balance list, the activity feed, the
/// split rows, Insights. The color is `MemberColor`, hashed from the display
/// name so the same person keeps the same color on every device; white
/// initials clear WCAG AA on the swatch at every hue (see `MemberColor`).
struct MemberAvatar: View {
    let name: String
    var size: CGFloat = 32

    init(name: String, size: CGFloat = 32) {
        self.name = name
        self.size = size
    }

    init(_ member: Member, size: CGFloat = 32) {
        self.init(name: member.displayName, size: size)
    }

    var body: some View {
        Text(Self.initials(from: name))
            .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(MemberColor.color(for: name), in: Circle())
            // The name itself is always adjacent for VoiceOver; the swatch is
            // decoration.
            .accessibilityHidden(true)
    }

    /// One or two uppercased letters for the swatch: the first letter of the
    /// first and last words for a multi-word name, otherwise the first two
    /// characters of a single word. `"?"` when there's nothing usable.
    static func initials(from name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace)
        if words.count >= 2, let first = words.first?.first, let last = words.last?.first {
            return "\(first)\(last)".uppercased()
        }
        if let word = words.first {
            return String(word.prefix(2)).uppercased()
        }
        return "?"
    }
}
