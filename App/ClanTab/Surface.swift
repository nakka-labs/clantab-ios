import SwiftUI
import ClanTabKit

/// The app's surface-elevation scale (`CHECKLIST.md` "Tonal surface
/// elevation") — one small, named set of greys instead of scattered
/// `Color.secondary.opacity(…)` guesses and a reliance on whatever the
/// system grouped styles happen to be.
///
/// Four tiers, darkest-recessed to brightest-raised:
///   `well`  → a recess: a progress-bar track, a tile behind a glyph
///   `canvas`→ the ground everything sits on
///   `card`  → a card lifted off the canvas (Form/List row groups already
///             render at roughly this tier via the system grouped style)
///   `raised`→ a surface above a card: a selected chip, the balance hero
///
/// Each tier resolves per light/dark. They're plain greys today; the
/// `DESIGN_BIBLE.md` §2 hue tint (10–15% of the app's 250°) is a separate
/// checklist item that adjusts the numbers here in one place.
enum Surface {
    static let well = tier(light: 0.90, dark: 0.26)
    static let canvas = tier(light: 0.965, dark: 0.135)
    static let card = tier(light: 0.995, dark: 0.190)
    static let raised = tier(light: 1.0, dark: 0.235)

    /// A grey at the given OKLCH lightness per appearance (chroma 0 for now —
    /// see the type doc). Wrapped in a dynamic `UIColor` so one `Color`
    /// tracks the trait change.
    private static func tier(light: Double, dark: Double) -> Color {
        Color(uiColor: UIColor { traits in
            let lightness = traits.userInterfaceStyle == .dark ? dark : light
            let c = OKLCH.sRGB(hue: 250, lightness: lightness, chroma: 0)
            return UIColor(red: c.red, green: c.green, blue: c.blue, alpha: 1)
        })
    }
}
