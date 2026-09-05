import SwiftUI

/// The manual light/dark/system override (`FEATURE_BACKLOG.md` "Explicit
/// light/dark/system theme toggle"). SwiftUI already adapts automatically to
/// the system appearance — this just lets someone pin the app's look
/// independent of that, persisted via `@AppStorage` in `SettingsView` and
/// applied at the root in `ClanTabApp`.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` tells SwiftUI to fall back to the system setting — the only way
    /// `.preferredColorScheme` expresses "no override".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
