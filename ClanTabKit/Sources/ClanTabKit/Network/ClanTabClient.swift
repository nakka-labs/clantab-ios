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
public actor ClanTabClient {
    private let baseURL: URL
    private let transport: ClanTabTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter baseURL: must have a trailing slash (e.g. `https://clantab.example.com/`)
    ///   so relative API paths resolve correctly.
    public init(baseURL: URL, transport: ClanTabTransport = URLSessionTransport()) {
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

    // MARK: - Group & member settings (DESIGN.md §2)

    /// Rename the group and/or change its default currency for new expenses.
    /// Existing expenses keep their own currency.
    public func updateGroup(groupId: String, name: String? = nil, currency: String? = nil) async throws -> UpdateGroupResponse {
        try await patch("api/groups/\(groupId)", body: UpdateGroupRequest(name: name, currency: currency))
    }

    public func renameMember(groupId: String, memberId: String, displayName: String) async throws -> JoinGroupResponse {
        try await patch("api/groups/\(groupId)/members/\(memberId)", body: JoinGroupRequest(displayName: displayName))
    }

    /// Remove a member. Throws `.server(code: "MEMBER_IN_USE", …)` if they're on
    /// any expense/settlement, linked to an account, or the last member.
    public func removeMember(groupId: String, memberId: String) async throws {
        var request = URLRequest(url: url(for: "api/groups/\(groupId)/members/\(memberId)"))
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    // MARK: - Edit / delete (DESIGN.md §2)

    /// Replace an expense wholesale. `request.id` is ignored — the id in the path
    /// identifies the row. The server keeps its position in the activity feed.
    public func updateExpense(groupId: String, expenseId: String, _ request: AddExpenseRequest) async throws -> AddExpenseResponse {
        try await put("api/groups/\(groupId)/expenses/\(expenseId)", body: request)
    }

    /// Remove an expense (and its splits). Idempotent — deleting one that's
    /// already gone still succeeds.
    public func deleteExpense(groupId: String, expenseId: String) async throws {
        var request = URLRequest(url: url(for: "api/groups/\(groupId)/expenses/\(expenseId)"))
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    public func updateSettlement(groupId: String, settlementId: String, _ request: AddSettlementRequest) async throws -> AddSettlementResponse {
        try await put("api/groups/\(groupId)/settlements/\(settlementId)", body: request)
    }

    public func deleteSettlement(groupId: String, settlementId: String) async throws {
        var request = URLRequest(url: url(for: "api/groups/\(groupId)/settlements/\(settlementId)"))
        request.httpMethod = "DELETE"
        try await performNoContent(request)
    }

    // MARK: - Accounts (ACCOUNTS_DESIGN.md §5–§7, §11)

    /// Exchange an Apple identity token for a session token + the identity's
    /// group list. Called once per sign-in. `authorizationCode` (from the same
    /// credential) lets the server set up revocation for account deletion.
    public func signInWithApple(identityToken: String, authorizationCode: String? = nil) async throws -> SessionResponse {
        try await post(
            "api/auth/apple",
            body: AppleSignInRequest(identityToken: identityToken, authorizationCode: authorizationCode)
        )
    }

    /// Trade a still-valid session token for a fresh one (§3). The app calls this
    /// on launch when the current token is within ~7 days of expiry.
    public func refreshSession(token: String) async throws -> SessionResponse {
        try await send("POST", "api/auth/refresh", bearer: token)
    }

    /// The signed-in identity's groups, authoritative from the server (§7).
    public func myGroups(token: String) async throws -> MyGroupsResponse {
        try await get("api/auth/groups", bearer: token)
    }

    /// Cross-group settling: the net owed to/from each linked person across
    /// shared groups (`FEATURE_BACKLOG.md`). "Settle All" then fires an ordinary
    /// `addSettlement` per `CrossGroupEdge`.
    public func peopleAcrossGroups(token: String) async throws -> PeopleAcrossGroupsResponse {
        try await get("api/auth/people", bearer: token)
    }

    /// Delete the account: every claimed membership reverts to a placeholder and
    /// the server-side index is wiped (§11). Groups and expenses are untouched.
    public func deleteAccount(token: String) async throws {
        var request = URLRequest(url: url(for: "api/auth/account"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try await performNoContent(request)
    }

    /// This group's placeholder members — the "this is me" picker (§6).
    public func claimableMembers(groupId: String, token: String) async throws -> ClaimableMembersResponse {
        try await get("api/groups/\(groupId)/claimable", bearer: token)
    }

    /// Link a placeholder member in this group to the signed-in identity (§6).
    public func claimMember(groupId: String, memberId: String, token: String) async throws -> ClaimMemberResponse {
        try await send("POST", "api/groups/\(groupId)/members/\(memberId)/claim", bearer: token)
    }

    // MARK: - Request plumbing

    private func get<Response: Decodable>(_ path: String, bearer: String? = nil) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "GET"
        setBearer(bearer, on: &request)
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearer: String? = nil) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        setBearer(bearer, on: &request)
        return try await perform(request)
    }

    private func put<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearer: String? = nil) async throws -> Response {
        try await bodyRequest("PUT", path, body: body, bearer: bearer)
    }

    private func patch<Body: Encodable, Response: Decodable>(_ path: String, body: Body, bearer: String? = nil) async throws -> Response {
        try await bodyRequest("PATCH", path, body: body, bearer: bearer)
    }

    private func bodyRequest<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body, bearer: String?) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        setBearer(bearer, on: &request)
        return try await perform(request)
    }

    /// A bodyless request (`POST /api/auth/refresh`, the claim routes) that still
    /// expects a decodable response.
    private func send<Response: Decodable>(_ method: String, _ path: String, bearer: String?) async throws -> Response {
        var request = URLRequest(url: url(for: path))
        request.httpMethod = method
        setBearer(bearer, on: &request)
        return try await perform(request)
    }

    private func setBearer(_ token: String?, on request: inout URLRequest) {
        guard let token else { return }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    private func url(for path: String) -> URL {
        URL(string: path, relativeTo: baseURL)!
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, statusCode) = try await transport.send(request)
        try checkStatus(data, statusCode)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw ClanTabClientError.decodingFailed(String(describing: error))
        }
    }

    /// For `204 No Content` responses (account deletion) — success is the absence
    /// of an error, there's nothing to decode.
    private func performNoContent(_ request: URLRequest) async throws {
        let (data, statusCode) = try await transport.send(request)
        try checkStatus(data, statusCode)
    }

    private func checkStatus(_ data: Data, _ statusCode: Int) throws {
        guard (200..<300).contains(statusCode) else {
            if let envelope = try? decoder.decode(ErrorEnvelope.self, from: data) {
                throw ClanTabClientError.server(code: envelope.error.code, message: envelope.error.message)
            }
            if statusCode == 404 {
                throw ClanTabClientError.notFound
            }
            throw ClanTabClientError.invalidResponse
        }
    }
}
