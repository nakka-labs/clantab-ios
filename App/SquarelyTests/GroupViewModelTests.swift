import XCTest
import SquareKit
@testable import Squarely

final class GroupViewModelTests: XCTestCase {

    func testBareNotFoundCountsAsGroupNotFound() {
        XCTAssertTrue(GroupViewModel.isGroupNotFound(SquarelyClientError.notFound))
    }

    func testStructuredGroupNotFoundEnvelopeCounts() {
        let error = SquarelyClientError.server(code: "GROUP_NOT_FOUND", message: "Group not found.")
        XCTAssertTrue(GroupViewModel.isGroupNotFound(error))
    }

    func testOtherServerErrorsDoNotCount() {
        let error = SquarelyClientError.server(code: "SPLIT_MISMATCH", message: "…")
        XCTAssertFalse(GroupViewModel.isGroupNotFound(error))
    }

    func testTransportFailuresDoNotCount() {
        XCTAssertFalse(GroupViewModel.isGroupNotFound(SquarelyClientError.invalidResponse))
        XCTAssertFalse(GroupViewModel.isGroupNotFound(URLError(.notConnectedToInternet)))
    }

    @MainActor
    func testRefetchFlagsGroupUnavailableOnNotFound() async {
        let vm = GroupViewModel(
            groupId: "dead-group",
            client: SquarelyClient(baseURL: URL(string: "https://example.invalid/")!, transport: NotFoundTransport()),
            identityStore: InMemoryIdentityStore()
        )
        await vm.refetch()
        XCTAssertTrue(vm.groupUnavailable)
        XCTAssertNil(vm.state)
    }

    @MainActor
    func testRefetchDoesNotFlagGroupUnavailableOnOtherErrors() async {
        let vm = GroupViewModel(
            groupId: "g",
            client: SquarelyClient(baseURL: URL(string: "https://example.invalid/")!, transport: ServerErrorTransport()),
            identityStore: InMemoryIdentityStore()
        )
        await vm.refetch()
        XCTAssertFalse(vm.groupUnavailable)
        XCTAssertNotNil(vm.errorMessage)
    }
}

/// Always responds 404 with no body — the shape `GET /api/groups/:groupId`
/// returns for a group that no longer exists.
private struct NotFoundTransport: SquarelyTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        (data: Data(), statusCode: 404)
    }
}

/// Responds with a structured non-404 error envelope.
private struct ServerErrorTransport: SquarelyTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        (data: Data(#"{"error":{"code":"RATE_LIMITED","message":"Slow down."}}"#.utf8), statusCode: 429)
    }
}
