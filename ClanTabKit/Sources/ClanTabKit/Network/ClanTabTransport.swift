import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstracts the actual HTTP transport so `ClanTabClient` can be tested without
/// touching the network or platform URL-loading internals — tests inject a fake
/// conforming to this protocol instead of exercising a real `URLSession`.
public protocol ClanTabTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int)
}

/// Default transport, backed by `URLSession`.
public struct URLSessionTransport: ClanTabTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        // The worker sends no `Cache-Control` on any response, and every
        // request here builds a plain `URLRequest` (default `.useProtocol
        // CachePolicy`) — against `.shared`'s persistent on-disk `URLCache`,
        // that's enough for a `GET` to be served from a stale cache entry
        // forever, never touching the network again once one response is
        // cached. Confirmed live: `fetchGroupState`'s foreground poll kept
        // returning `cache_hit=true` with the exact byte count of the
        // *first* response, for 5+ minutes, straight through server-side
        // changes that should have shown up (a real "someone else added an
        // expense while I'm looking at this screen" scenario, not an edge
        // case). `.reloadIgnoringLocalCacheData` forces every request onto
        // the network, matching the sync model's own assumption (`DESIGN.md`
        // §7) that a poll always reflects the server's current state.
        var request = request
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ClanTabClientError.invalidResponse
        }
        return (data, http.statusCode)
    }
}
