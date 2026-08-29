import Foundation

/// App-wide configuration.
enum AppConfig {
    /// The deployed Cloudflare Worker (`worker/`, `DESIGN.md` §2). Must end with
    /// a trailing slash so relative API paths in `ClanTabClient` resolve
    /// correctly. For local development run `make worker-dev` and temporarily
    /// swap this for `http://localhost:8787/`.
    static let apiBaseURL = URL(string: "https://clantab.nakka-labs.workers.dev/")!

    /// The user-facing capability link for a group (`DESIGN.md` §1), served by
    /// the same Worker origin as the API at `/g/:groupId` (§8: same-origin,
    /// no separate web host to configure).
    static func groupShareURL(groupId: String) -> URL {
        URL(string: "g/\(groupId)", relativeTo: apiBaseURL)!
    }
}
