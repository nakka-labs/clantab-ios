import Foundation

/// A pastel, formula-driven color per category (`FEATURE_BACKLOG.md`
/// "Category colors, formula-driven, not hand-picked") — `DESIGN_BIBLE.md`
/// §2's `oklch(55% 0.16 H)` brand-accent formula at a pale pastel band
/// (higher lightness, lower chroma), with the hue derived deterministically
/// from the category name rather than hand-picked, so every category —
/// including free-form ones a user types — gets a distinct, consistent color
/// for free, the same on every device.
///
/// The hue hash and the OKLCH → sRGB conversion live in `OKLCH`, shared with
/// `MemberColor` (the higher-chroma band); this type just pins the band.
public enum CategoryColor {
    /// `oklch(88% 0.07 H)` — noticeably lighter/less saturated than the
    /// brand accent's `55%`/`0.16`, which is what makes it read as "pastel"
    /// rather than a second brand color.
    public static let lightness: Double = 0.88
    public static let chroma: Double = 0.07

    /// A stable hue in `[0, 360)` for a category name (see `OKLCH.hue(for:)`).
    public static func hue(for categoryName: String) -> Double {
        OKLCH.hue(for: categoryName)
    }

    /// The pastel swatch for a category name, as sRGB components in `[0, 1]`.
    public static func rgb(for categoryName: String) -> (red: Double, green: Double, blue: Double) {
        rgb(hue: hue(for: categoryName), lightness: lightness, chroma: chroma)
    }

    /// OKLCH → sRGB (see `OKLCH.sRGB(hue:lightness:chroma:)`).
    public static func rgb(hue: Double, lightness: Double, chroma: Double) -> (red: Double, green: Double, blue: Double) {
        OKLCH.sRGB(hue: hue, lightness: lightness, chroma: chroma)
    }
}
