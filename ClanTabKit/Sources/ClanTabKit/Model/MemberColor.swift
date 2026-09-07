import Foundation

/// A formula-driven identity color per member (`CHECKLIST.md` "Member
/// identity color/avatar") — `DESIGN_BIBLE.md` §2's one color formula at a
/// higher-chroma band than `CategoryColor`'s pale pastel, so a member's
/// initials-on-swatch avatar reads as a confident, saturated color rather
/// than a washed-out tint, while still being the same formula (not a second,
/// hand-picked palette).
///
/// The hue is hashed from the member's display name, so the same person keeps
/// the same color on every device with no shared table to sync. The hue hash
/// and the OKLCH → sRGB conversion live in `OKLCH`, shared with
/// `CategoryColor`; this type just pins the band.
///
/// Pure math, no UIKit/SwiftUI dependency (the cross-platform guardrail in
/// `AGENTS.md`) — the App target converts the sRGB components into a `Color`.
public enum MemberColor {
    /// `oklch(50% 0.17 H)` — deeper and far more saturated than
    /// `CategoryColor`'s pastel `88%`/`0.07`, and a touch deeper than the
    /// brand accent's `55%`/`0.16`, so members sit in their own band: vivid,
    /// not pastel, not the brand color. At this band, white text clears WCAG
    /// AA (≥ 4.5:1 contrast) on the swatch across the entire hue circle, so
    /// the avatar always draws its initials in white.
    public static let lightness: Double = 0.50
    public static let chroma: Double = 0.17

    /// A stable hue in `[0, 360)` for a member's display name (see
    /// `OKLCH.hue(for:)`).
    public static func hue(for displayName: String) -> Double {
        OKLCH.hue(for: displayName)
    }

    /// The identity swatch for a member's display name, as sRGB components in
    /// `[0, 1]`.
    public static func rgb(for displayName: String) -> (red: Double, green: Double, blue: Double) {
        OKLCH.sRGB(hue: hue(for: displayName), lightness: lightness, chroma: chroma)
    }
}
