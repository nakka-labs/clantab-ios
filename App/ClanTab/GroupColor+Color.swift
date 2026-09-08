import SwiftUI
import ClanTabKit

extension GroupColor {
    /// The group's accent as a SwiftUI `Color` — a thin wrapper around
    /// ClanTabKit's pure `GroupColor.rgb(forId:)`, same split as
    /// `MemberColor.color(for:)`.
    static func color(forId groupId: String) -> Color {
        swatch(forId: groupId, lightness: lightness)
    }

    /// A slightly darker take on the group's hue (`oklch 50%`, the
    /// `MemberColor` band) for a solid badge that carries white text — the
    /// header-accent `color(forId:)` at `55%` is a touch light for that.
    static func badge(forId groupId: String) -> Color {
        swatch(forId: groupId, lightness: 0.50)
    }

    /// The group's hue converted to a SwiftUI `Color` at a given point on the
    /// OKLCH lightness scale — `color(forId:)` and `badge(forId:)` differ only
    /// in that constant, so the `OKLCH.sRGB` call lives here once.
    private static func swatch(forId groupId: String, lightness: Double) -> Color {
        let c = OKLCH.sRGB(hue: hue(forId: groupId), lightness: lightness, chroma: chroma)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    /// The group's hue at the two points on the sanctioned lightness scale
    /// (`DESIGN_BIBLE.md` §3's two-stop gradient — `oklch 60% → 40%`, the
    /// same stop-pair as the icon and `RecapCard.brandGradient`). Used as a
    /// low-opacity wash on the balance hero card so it carries the group's
    /// identity with a hint of depth rather than a flat tint.
    static func wash(forId groupId: String) -> LinearGradient {
        let h = hue(forId: groupId)
        let top = OKLCH.sRGB(hue: h, lightness: 0.60, chroma: 0.15)
        let bottom = OKLCH.sRGB(hue: h, lightness: 0.40, chroma: 0.14)
        return LinearGradient(
            colors: [
                Color(red: top.red, green: top.green, blue: top.blue).opacity(0.16),
                Color(red: bottom.red, green: bottom.green, blue: bottom.blue).opacity(0.05),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
