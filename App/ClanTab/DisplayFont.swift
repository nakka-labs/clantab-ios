import SwiftUI

/// The portfolio display face (`DESIGN_BIBLE.md` §1) — Space Grotesk, self-hosted
/// (SIL OFL), the one deliberate exception to "system fonts only". Used *only*
/// for the ClanTab wordmark and hero numerals (the balance, the Insights total,
/// the recap card) — never body text, chrome, or iconography.
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
    /// anchored to `textStyle` for the scaling curve.
    static func display(size: CGFloat, weight: DisplayWeight = .semibold, relativeTo textStyle: Font.TextStyle = .largeTitle) -> Font {
        .custom(weight.faceName, size: size, relativeTo: textStyle)
    }

    /// Display face sized like the system large title (34pt), for the wordmark.
    static func display(weight: DisplayWeight = .bold) -> Font {
        .custom(weight.faceName, size: 34, relativeTo: .largeTitle)
    }
}
