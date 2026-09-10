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

/// A member's avatar — their profile photo (`CHECKLIST.md` "Profile photos")
/// when one is set and resolves, otherwise their initials on the
/// formula-driven `MemberColor` circle (`DESIGN_BIBLE.md` §2). The shared
/// avatar used everywhere a member shows up: the balance list, the activity
/// feed, the split rows, Insights. White initials clear WCAG AA on the swatch
/// at every hue (see `MemberColor`).
///
/// Photo loading goes through `AvatarImageLoader` in the environment; a view
/// without it (previews, tests, or a call site that only has a name) just
/// shows initials.
struct MemberAvatar: View {
    let name: String
    var size: CGFloat = 32
    /// The R2 key of this member's photo, from `Member.avatarKey` — `nil` for a
    /// guest, a photoless identity, or a name-only call site.
    var avatarKey: String?

    @Environment(\.avatarImageLoader) private var loader
    @State private var photo: UIImage?

    init(name: String, size: CGFloat = 32) {
        self.name = name
        self.size = size
        self.avatarKey = nil
    }

    /// For a call site that has a name + photo key but no `Member` — e.g. the
    /// signed-in user's own avatar in Settings.
    init(name: String, avatarKey: String?, size: CGFloat = 32) {
        self.name = name
        self.size = size
        self.avatarKey = avatarKey
    }

    init(_ member: Member, size: CGFloat = 32) {
        self.name = member.displayName
        self.size = size
        self.avatarKey = member.avatarKey
    }

    var body: some View {
        avatar
            // The name itself is always adjacent for VoiceOver; the swatch is
            // decoration.
            .accessibilityHidden(true)
            // `generation` moves when a photo is replaced/removed even though
            // the key (stable per identity) doesn't — re-resolve on both.
            .task(id: AvatarTaskID(key: avatarKey, generation: loader?.generation ?? 0)) {
                guard let avatarKey, let loader else {
                    photo = nil
                    return
                }
                if let hit = loader.cached(avatarKey) {
                    photo = hit
                } else {
                    photo = await loader.load(avatarKey)
                }
            }
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Text(Self.initials(from: name))
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(MemberColor.color(for: name), in: Circle())
        }
    }

    private struct AvatarTaskID: Equatable {
        let key: String?
        let generation: Int
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
