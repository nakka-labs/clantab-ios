import SwiftUI
import ClanTabKit

extension GroupColor {
    /// The group's accent as a SwiftUI `Color` — a thin wrapper around
    /// ClanTabKit's pure `GroupColor.rgb(forId:)`, same split as
    /// `MemberColor.color(for:)`.
    static func color(forId groupId: String) -> Color {
        let c = rgb(forId: groupId)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
