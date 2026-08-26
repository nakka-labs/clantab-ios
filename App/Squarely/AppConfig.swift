import Foundation

/// App-wide configuration.
enum AppConfig {
    /// Must end with a trailing slash so relative API paths in `SquarelyClient`
    /// resolve correctly (see `DESIGN.md` §2).
    ///
    /// TODO: point this at the deployed Cloudflare Worker once the backend is
    /// live. Use `http://localhost:8787/` for local `wrangler dev` testing.
    static let apiBaseURL = URL(string: "https://squarely-api.example.workers.dev/")!
}
