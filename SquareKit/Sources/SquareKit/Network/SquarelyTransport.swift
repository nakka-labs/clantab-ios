import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Abstracts the actual HTTP transport so `SquarelyClient` can be tested without
/// touching the network or platform URL-loading internals — tests inject a fake
/// conforming to this protocol instead of exercising a real `URLSession`.
public protocol SquarelyTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int)
}

/// Default transport, backed by `URLSession`.
public struct URLSessionTransport: SquarelyTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SquarelyClientError.invalidResponse
        }
        return (data, http.statusCode)
    }
}
