import Foundation

/// Errors surfaced by `SquarelyClient`: the server's structured error envelope
/// (`DESIGN.md` §2 — `{ "error": { "code", "message" } }`) plus local/transport
/// failures.
public enum SquarelyClientError: Error, Equatable, Sendable {
    /// A structured error the server returned, e.g. `.server(code: "SPLIT_MISMATCH", message: "...")`.
    case server(code: String, message: String)
    /// A non-2xx response with no structured error body (the resolve-join-code route
    /// per `DESIGN.md` §2 returns a bare 404 for an unknown code).
    case notFound
    /// The transport didn't return an HTTP response at all.
    case invalidResponse
    /// A 2xx response body didn't match the expected shape.
    case decodingFailed(String)
}
