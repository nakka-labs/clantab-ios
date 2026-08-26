import Foundation

/// App-wide configuration.
enum AppConfig {
    /// Must end with a trailing slash so relative API paths in `SquarelyClient`
    /// resolve correctly (see `DESIGN.md` §2).
    ///
    /// TODO: point this at the deployed Cloudflare Worker once the backend is
    /// live. Use `http://localhost:8787/` for local `wrangler dev` testing.
    static let apiBaseURL = URL(string: "https://squarely-api.example.workers.dev/")!

    /// The user-facing capability link for a group (`DESIGN.md` §1), served by
    /// the same Worker origin as the API at `/g/:groupId` (§8: same-origin,
    /// no separate web host to configure).
    static func groupShareURL(groupId: String) -> URL {
        URL(string: "g/\(groupId)", relativeTo: apiBaseURL)!
    }
}
