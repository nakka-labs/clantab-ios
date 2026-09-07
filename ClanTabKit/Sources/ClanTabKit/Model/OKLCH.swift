import Foundation

/// `DESIGN_BIBLE.md` §2's one color formula, in one place.
///
/// The brand accent is `oklch(55% 0.16 H)` with `H` fixed per app. The same
/// construction generalizes: within an app that has many like things a person
/// must tell apart at a glance, hash a stable identifier to a hue and reuse the
/// formula at a per-use lightness/chroma *band*. `CategoryColor` (a pale pastel
/// band) and `MemberColor` (a higher-chroma band) are two bands on this one
/// formula, not two systems — so the hue hash and the OKLCH → sRGB conversion
/// live here, shared, rather than being copied per band.
///
/// Pure math, no UIKit/SwiftUI dependency (the cross-platform guardrail in
/// `AGENTS.md` keeps Apple-only frameworks out of this package) — call sites
/// convert the resulting sRGB components into a `Color`.
public enum OKLCH {
    /// A stable hue in `[0, 360)` for an identifier — the same string always
    /// maps to the same hue, case-insensitively, with no shared table to keep
    /// in sync across clients (djb2 string hash, mod 360).
    public static func hue(for identifier: String) -> Double {
        var hash: UInt64 = 5381
        for scalar in identifier.lowercased().unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ UInt64(scalar.value)
        }
        return Double(hash % 360)
    }

    /// OKLCH → sRGB, via Björn Ottosson's OKLab
    /// (https://bottosson.github.io/posts/oklab/). `hue` is in degrees;
    /// `lightness`/`chroma` are OKLab's native scale — `oklch(55% 0.16 H)`'s
    /// "55%" is `lightness: 0.55`, not a 0–100 percent value.
    public static func sRGB(hue: Double, lightness: Double, chroma: Double) -> (red: Double, green: Double, blue: Double) {
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
