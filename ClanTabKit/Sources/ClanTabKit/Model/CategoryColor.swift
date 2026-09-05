import Foundation

/// A pastel, formula-driven color per category (`FEATURE_BACKLOG.md`
/// "Category colors, formula-driven, not hand-picked") — extends
/// `DESIGN_BIBLE.md` §2's `oklch(55% 0.16 H)` brand-accent formula: same
/// construction, a pastel variant (higher lightness, lower chroma), with the
/// hue derived deterministically from the category name rather than
/// hand-picked, so every category — including free-form ones a user types —
/// gets a distinct, consistent color for free, the same on every device.
///
/// Pure math, no UIKit/SwiftUI dependency (the cross-platform guardrail in
/// `AGENTS.md` keeps Apple-only frameworks out of this package) — the App
/// target converts the resulting sRGB components into a `Color`.
public enum CategoryColor {
    /// `oklch(88% 0.07 H)` — noticeably lighter/less saturated than the
    /// brand accent's `55%`/`0.16`, which is what makes it read as "pastel"
    /// rather than a second brand color.
    public static let lightness: Double = 0.88
    public static let chroma: Double = 0.07

    /// A stable hue in `[0, 360)` for a category name — the same name always
    /// maps to the same hue, case-insensitively, with no shared table to
    /// keep in sync across clients (djb2 string hash, mod 360).
    public static func hue(for categoryName: String) -> Double {
        var hash: UInt64 = 5381
        for scalar in categoryName.lowercased().unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return Double(hash % 360)
    }

    /// The pastel swatch for a category name, as sRGB components in `[0, 1]`.
    public static func rgb(for categoryName: String) -> (red: Double, green: Double, blue: Double) {
        rgb(hue: hue(for: categoryName), lightness: lightness, chroma: chroma)
    }

    /// OKLCH → sRGB, via Björn Ottosson's OKLab
    /// (https://bottosson.github.io/posts/oklab/). `hue` is in degrees;
    /// `lightness`/`chroma` are OKLab's native scale — `oklch(55% 0.16 H)`'s
    /// "55%" is `lightness: 0.55`, not a 0–100 percent value.
    public static func rgb(hue: Double, lightness: Double, chroma: Double) -> (red: Double, green: Double, blue: Double) {
        let hueRadians = hue * .pi / 180
        let a = chroma * cos(hueRadians)
        let b = chroma * sin(hueRadians)

        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b

        let l = l_ * l_ * l_
        let m = m_ * m_ * m_
        let s = s_ * s_ * s_

        let rLinear = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
        let gLinear = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
        let bLinear = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s

        return (gammaEncode(rLinear), gammaEncode(gLinear), gammaEncode(bLinear))
    }

    /// Linear sRGB → gamma-encoded sRGB, clamped to `[0, 1]` — OKLab can
    /// produce slightly out-of-gamut values at extreme hues, which would
    /// otherwise turn into a nonsensical `Color`.
    private static func gammaEncode(_ linear: Double) -> Double {
        let clamped = min(max(linear, 0), 1)
        return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    }
}
