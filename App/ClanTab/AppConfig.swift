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
    /// no separate web host to configure).
    static func groupShareURL(groupId: String) -> URL {
        URL(string: "g/\(groupId)", relativeTo: apiBaseURL)!
    }

    /// The iOS OAuth client id from Google Cloud Console
    /// (`MANDATORY_LOGIN_PLAN.md` Part 1) — the `aud` the worker's
    /// `POST /api/auth/google` checks a Google identity token against.
    static let googleClientID = "785063933196-ieaukpoat5r6v5jjr65315o9rniaaahn.apps.googleusercontent.com"

    /// `googleClientID` with its dot-delimited fields reversed — the redirect
    /// scheme Google's "iOS" OAuth client type expects, registered as a
    /// `CFBundleURLTypes` entry in `App/project.yml`.
    static let googleReversedClientID = "com.googleusercontent.apps.785063933196-ieaukpoat5r6v5jjr65315o9rniaaahn"
}
