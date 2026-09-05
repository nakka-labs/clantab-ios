import Foundation

/// App-wide configuration.
enum AppConfig {
    /// The deployed Cloudflare Worker (`worker/`, `DESIGN.md` §2). Must end with
    /// a trailing slash so relative API paths in `ClanTabClient` resolve
    /// correctly. For local development run `make worker-dev` and temporarily
    /// swap this for `http://localhost:8787/`.
    static let apiBaseURL = URL(string: "https://clantab.nakka-labs.workers.dev/")!

    /// Currencies offered in the pickers (group creation, add expense). Every
    /// one has 2 decimal minor units — see `MoneyFormat`.
    static let supportedCurrencies = ["INR", "USD", "EUR", "GBP", "AUD", "CAD"]

    /// The user-facing capability link for a group (`DESIGN.md` §1), served by
    /// the same Worker origin as the API at `/g/:groupId` (§8: same-origin,
    /// no separate web host to configure). `accessToken` (`ACCESS_TOKEN_PLAN.md`)
    /// rides along as `?token=` when the group has one — `nil` for a group
    /// that predates the feature and was never regenerated, in which case the
    /// link is exactly what it always was.
    static func groupShareURL(groupId: String, accessToken: String? = nil) -> URL {
        let base = URL(string: "g/\(groupId)", relativeTo: apiBaseURL)!
        guard let accessToken else { return base }
        var components = URLComponents(url: base, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        return components.url!
    }

    /// The iOS OAuth client id from Google Cloud Console
    /// (`MANDATORY_LOGIN_PLAN.md` Part 1) — the `aud` the worker's
    /// `POST /api/auth/google` checks a Google identity token against.
    static let googleClientID = "785063933196-ieaukpoat5r6v5jjr65315o9rniaaahn.apps.googleusercontent.com"

    /// `googleClientID` with its dot-delimited fields reversed — the redirect
    /// scheme Google's "iOS" OAuth client type expects, registered as a
    /// `CFBundleURLTypes` entry in `App/project.yml`.
    static let googleReversedClientID = "com.googleusercontent.apps.785063933196-ieaukpoat5r6v5jjr65315o9rniaaahn"

    // MARK: - Home-screen widget (FEATURE_BACKLOG.md)
    //
    // This file is a member of both the `ClanTab` and `ClanTabWidgetExtension`
    // targets (`App/project.yml`) — the widget extension runs in a separate
    // process with no other way to see these values.

    /// Shared between the app and `ClanTabWidgetExtension` — the only channel
    /// an app extension has for reading anything the containing app wrote.
    /// Needs the matching App Groups capability enabled on both targets' App
    /// IDs in the Apple Developer portal before a TestFlight build, same
    /// caveat as Sign in with Apple / push notifications above; a local
    /// Simulator build works via Xcode's automatic-signing App Group
    /// creation.
    static let appGroupID = "group.com.clantab.app"

    /// `UserDefaults(suiteName:)` can fail (a malformed suite id, or the App
    /// Group entitlement not actually provisioned yet) — falls back to
    /// `.standard` so a missing/not-yet-enabled capability degrades to "the
    /// widget shows its empty state," never a crash.
    static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    /// The one home-screen widget's kind identifier — must match
    /// `ClanTabBalanceWidget`'s own declaration exactly, since `WidgetCenter`
    /// addresses widgets by this string, not by type.
    static let balanceWidgetKind = "ClanTabBalanceWidget"
}
