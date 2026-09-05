import XCTest
import ClanTabKit
@testable import ClanTab

final class GroupViewModelTests: XCTestCase {

    func testBareNotFoundCountsAsGroupNotFound() {
        XCTAssertTrue(GroupViewModel.isGroupNotFound(ClanTabClientError.notFound))
    }

    func testStructuredGroupNotFoundEnvelopeCounts() {
        let error = ClanTabClientError.server(code: "GROUP_NOT_FOUND", message: "Group not found.")
        XCTAssertTrue(GroupViewModel.isGroupNotFound(error))
    }

    func testOtherServerErrorsDoNotCount() {
        let error = ClanTabClientError.server(code: "SPLIT_MISMATCH", message: "…")
        XCTAssertFalse(GroupViewModel.isGroupNotFound(error))
    }

    func testTransportFailuresDoNotCount() {
        XCTAssertFalse(GroupViewModel.isGroupNotFound(ClanTabClientError.invalidResponse))
        XCTAssertFalse(GroupViewModel.isGroupNotFound(URLError(.notConnectedToInternet)))
    }

    @MainActor
    func testRefetchFlagsGroupUnavailableOnNotFound() async {
        let vm = GroupViewModel(
            groupId: "dead-group",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: NotFoundTransport()),
            auth: makeAuth()
        )
        await vm.refetch()
        XCTAssertTrue(vm.groupUnavailable)
        XCTAssertNil(vm.state)
    }

    @MainActor
    func testRefetchDoesNotFlagGroupUnavailableOnOtherErrors() async {
        let vm = GroupViewModel(
            groupId: "g",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: ServerErrorTransport()),
            auth: makeAuth()
        )
        await vm.refetch()
        XCTAssertFalse(vm.groupUnavailable)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testAutoRefetchFlagsGroupUnavailableOnNotFound() async {
        let vm = GroupViewModel(
            groupId: "dead-group",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: NotFoundTransport()),
            auth: makeAuth()
        )
        await vm.autoRefetch()
        XCTAssertTrue(vm.groupUnavailable)
    }

    /// Unlike `refetch()`, a background poll stays silent on a transient
    /// failure — no error banner, and (in the real app) the last good state is
    /// left on screen.
    @MainActor
    func testAutoRefetchStaysSilentOnTransientError() async {
        let vm = GroupViewModel(
            groupId: "g",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: ServerErrorTransport()),
            auth: makeAuth()
        )
        await vm.autoRefetch()
        XCTAssertFalse(vm.groupUnavailable)
        XCTAssertNil(vm.errorMessage)
    }

    /// A minimal signed-out `AuthViewModel` — these tests exercise `refetch`/
    /// `autoRefetch`, not `myIdentity`, so an empty `groups` list is fine.
    @MainActor
    private func makeAuth() -> AuthViewModel {
        AuthViewModel(
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: NotFoundTransport()),
            sessionStore: InMemorySessionStore(),
            knownGroups: InMemoryKnownGroupsStore(),
            syncNudge: InMemorySyncNudgeStore()
        )
    }

    // MARK: - widget snapshot (FEATURE_BACKLOG.md "Home-screen widget")

    @MainActor
    private func makeSignedInAuth(memberId: String) async -> AuthViewModel {
        let session = StoredSession(token: "sess-tok", provider: .apple, appleUserID: "u1", expiresAt: Date().addingTimeInterval(3600))
        let auth = AuthViewModel(
            client: ClanTabClient(
                baseURL: URL(string: "https://example.invalid/")!,
                transport: GroupsTransport(groupId: "g", memberId: memberId)
            ),
            sessionStore: InMemorySessionStore(session),
            knownGroups: InMemoryKnownGroupsStore(),
            syncNudge: InMemorySyncNudgeStore()
        )
        await auth.refreshGroups()
        return auth
    }

    @MainActor
    func testRefetchWritesTheWidgetSnapshotForAClaimedMember() async {
        let snapshotStore = InMemoryWidgetSnapshotStore()
        let vm = GroupViewModel(
            groupId: "g",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: GroupStateTransport()),
            auth: await makeSignedInAuth(memberId: "m1"),
            widgetSnapshotStore: snapshotStore
        )

        await vm.refetch()

        let snapshot = snapshotStore.snapshot()
        XCTAssertEqual(snapshot?.groupId, "g")
        XCTAssertEqual(snapshot?.groupName, "Goa Trip")
        XCTAssertEqual(snapshot?.balances, [Balance(memberId: "m1", currency: "INR", netMinor: 100)])
    }

    @MainActor
    func testRefetchSkipsTheWidgetSnapshotWithoutAClaimedIdentity() async {
        let snapshotStore = InMemoryWidgetSnapshotStore()
        let vm = GroupViewModel(
            groupId: "g",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: GroupStateTransport()),
            auth: makeAuth(), // signed out — no claimed membership anywhere
            widgetSnapshotStore: snapshotStore
        )

        await vm.refetch()

        XCTAssertNil(snapshotStore.snapshot())
    }

    @MainActor
    func testAutoRefetchAlsoWritesTheWidgetSnapshot() async {
        let snapshotStore = InMemoryWidgetSnapshotStore()
        let vm = GroupViewModel(
            groupId: "g",
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: GroupStateTransport()),
            auth: await makeSignedInAuth(memberId: "m2"),
            widgetSnapshotStore: snapshotStore
        )

        await vm.autoRefetch()

        XCTAssertEqual(snapshotStore.snapshot()?.balances, [Balance(memberId: "m2", currency: "INR", netMinor: -100)])
    }
}

/// `GET /api/auth/groups` — one membership, in group "g" as `memberId`.
private struct GroupsTransport: ClanTabTransport {
    let groupId: String
    let memberId: String
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        let body = #"{"groups":[{"groupId":"\#(groupId)","memberId":"\#(memberId)","displayName":"Me"}]}"#
        return (Data(body.utf8), 200)
    }
}

/// `GET /api/groups/:groupId` — a minimal two-member group with a nonzero
/// balance for each, for the widget-snapshot tests above.
private struct GroupStateTransport: ClanTabTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        let body = """
        {
          "group": {"name": "Goa Trip", "currency": "INR", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2"},
          "members": [{"id": "m1", "displayName": "Alice"}, {"id": "m2", "displayName": "Bob"}],
          "expenses": [],
          "settlements": [],
          "balances": [
            {"memberId": "m1", "currency": "INR", "netMinor": 100},
            {"memberId": "m2", "currency": "INR", "netMinor": -100}
          ],
          "simplifiedSettlements": []
        }
        """
        return (Data(body.utf8), 200)
    }
}

/// Always responds 404 with no body — the shape `GET /api/groups/:groupId`
/// returns for a group that no longer exists.
private struct NotFoundTransport: ClanTabTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        (data: Data(), statusCode: 404)
    }
}

/// Responds with a structured non-404 error envelope.
private struct ServerErrorTransport: ClanTabTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        (data: Data(#"{"error":{"code":"RATE_LIMITED","message":"Slow down."}}"#.utf8), statusCode: 429)
    }
}
