import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Async/await HTTP client implementing the API contract in `DESIGN.md` §2.
///
/// This is the entire sync model (`DESIGN.md` §7): every mutation is a plain POST,
/// and callers are expected to follow up with `fetchGroupState` to pick up the
/// server-computed balances and simplified settlements — there's no optimistic UI
/// and no WebSocket in v1.
public actor SquarelyClient {
    private let baseURL: URL
    private let transport: SquarelyTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter baseURL: must have a trailing slash (e.g. `https://squarely.example.com/`)
    ///   so relative API paths resolve correctly.
    public init(baseURL: URL, transport: SquarelyTransport = URLSessionTransport()) {
        self.baseURL = baseURL
        self.transport = transport

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    public func createGroup(_ request: CreateGroupRequest) async throws -> CreateGroupResponse {
        try await post("api/groups", body: request)
    }

    public func resolveJoinCode(_ joinCode: String) async throws -> ResolveJoinCodeResponse {
        try await get("api/groups/resolve/\(joinCode)")
    }

    public func joinGroup(groupId: String, _ request: JoinGroupRequest) async throws -> JoinGroupResponse {
        try await post("api/groups/\(groupId)/members", body: request)
    }

    public func fetchGroupState(groupId: String) async throws -> GroupStateResponse {
        try await get("api/groups/\(groupId)")
    }

    public func addExpense(groupId: String, _ request: AddExpenseRequest) async throws -> AddExpenseResponse {
        try await post("api/groups/\(groupId)/expenses", body: request)
    }

    public func addSettlement(groupId: String, _ request: AddSettlementRequest) async throws -> AddSettlementResponse {
        try await post("api/groups/\(groupId)/settlements", body: request)
    }

    // MARK: - Request plumbing

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "GET"
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await perform(request)
    }

    private func url(for path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, statusCode) = try await transport.send(request)

        guard (200..<300).contains(statusCode) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw SquarelyClientError.server(code: envelope.error.code, message: envelope.error.message)
            }
            if statusCode == 404 {
                throw SquarelyClientError.notFound
            }
            throw SquarelyClientError.invalidResponse
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw SquarelyClientError.decodingFailed(String(describing: error))
        }
    }
}
