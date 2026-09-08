import SwiftUI

/// The portfolio display face (`DESIGN_BIBLE.md` §1) — Space Grotesk, self-hosted
/// (SIL OFL), the one deliberate exception to "system fonts only". Used *only*
/// for the ClanTab wordmark and hero numerals (the Insights total, the recap
/// card) — never body text, chrome, or iconography. The Group Home balance
/// stays on SF Rounded (owner call — Space Grotesk's ₹ and geometric digits
/// read calculator-ish at that size); see `BalanceHeroView.heroFont`.
///
/// Bundled as three static instances (`SpaceGrotesk-Medium/SemiBold/Bold`,
/// registered in `project.yml`'s `UIAppFonts`). `relativeTo:` ties each size to
/// a text style so it still scales with Dynamic Type.
enum DisplayWeight {
    case medium, semibold, bold

    var faceName: String {
        switch self {
        case .medium: return "SpaceGrotesk-Medium"
        case .semibold: return "SpaceGrotesk-SemiBold"
        case .bold: return "SpaceGrotesk-Bold"
        }
    }
}

extension Font {
    /// Display face at a fixed point size that still scales with Dynamic Type,
    /// anchored to `textStyle` for the scaling curve. Tabular figures
    /// (`DESIGN_BIBLE.md` §1) — a value that updates in place doesn't jiggle
    /// the layout around it, and the display face is only ever a hero numeral
    /// or the (digit-free) wordmark, so this is always the figure style we want.
    static func display(size: CGFloat, weight: DisplayWeight = .semibold, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom(weight.faceName, size: size, relativeTo: textStyle).monospacedDigit()
    }

    /// Display face sized like the system large title (34pt), for the wordmark.
    static func display(weight: DisplayWeight = .bold) -> Font {
        .custom(weight.faceName, size: 34, relativeTo: .largeTitle)
    }
}
