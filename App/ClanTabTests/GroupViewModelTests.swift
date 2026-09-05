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
