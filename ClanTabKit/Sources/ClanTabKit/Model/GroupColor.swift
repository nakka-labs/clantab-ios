import Foundation

/// A formula-driven identity colour per group (`CHECKLIST.md` "Per-group
/// accent color") — `DESIGN_BIBLE.md` §2's one colour formula with the hue
/// hashed from the group's permanent `id`, so a group keeps the same accent
/// everywhere and two groups read visibly differently without anyone picking
/// a colour. Used as a light header accent on Group Home and the groups
/// list, never to recolour the app's chrome (buttons/links stay the brand
/// hue).
///
/// The hue hash and the OKLCH → sRGB conversion live in `OKLCH`, shared with
/// `MemberColor` / `CategoryColor`; this type just pins the band — the same
/// `55% / 0.16` as the brand accent, so a group's colour reads as
/// "brand-family, this group's hue".
///
/// Pure math, no UIKit/SwiftUI dependency (the `AGENTS.md` cross-platform
/// guardrail) — the App target converts the sRGB components into a `Color`.
public enum GroupColor {
    public static let lightness: Double = 0.55
    public static let chroma: Double = 0.16

    /// A stable hue in `[0, 360)` for a group id (see `OKLCH.hue(for:)`).
    public static func hue(forId groupId: String) -> Double {
        OKLCH.hue(for: groupId)
    }

    /// The group's accent swatch, as sRGB components in `[0, 1]`.
    public static func rgb(forId groupId: String) -> (red: Double, green: Double, blue: Double) {
        OKLCH.sRGB(hue: hue(forId: groupId), lightness: lightness, chroma: chroma)
    }
}
