import XCTest
import ClanTabKit
@testable import ClanTab

final class AuthViewModelTests: XCTestCase {

    // MARK: - launchDecision (pure policy, ACCOUNTS_DESIGN.md §3)

    func testLaunchDecisionNoSession() {
        XCTAssertEqual(
            AuthViewModel.launchDecision(session: nil, standing: .noSession, now: .now),
            .none
        )
    }

    func testLaunchDecisionExpiredSessionIsDiscardedRegardlessOfStanding() {
        let expired = session(expiresIn: -60)
        for standing: CredentialStanding in [.authorized, .revoked, .notFound, .noSession] {
            XCTAssertEqual(
                AuthViewModel.launchDecision(session: expired, standing: standing, now: .now),
                .discard
            )
        }
    }

    func testLaunchDecisionRevokedOrMissingCredentialIsDiscarded() {
        let valid = session(expiresIn: 20 * day)
        XCTAssertEqual(AuthViewModel.launchDecision(session: valid, standing: .revoked, now: .now), .discard)
        XCTAssertEqual(AuthViewModel.launchDecision(session: valid, standing: .notFound, now: .now), .discard)
    }

    func testLaunchDecisionAuthorizedKeepsAFreshTokenAndRefreshesANearExpiryOne() {
        XCTAssertEqual(
            AuthViewModel.launchDecision(session: session(expiresIn: 20 * day), standing: .authorized, now: .now),
            .keep
        )
        XCTAssertEqual(
            AuthViewModel.launchDecision(session: session(expiresIn: 3 * day), standing: .authorized, now: .now),
            .refresh
        )
    }

    // MARK: - signIn

    @MainActor
    func testSignInStoresTheSessionAndGroups() async {
        let store = InMemorySessionStore()
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 200, json: """
            {"sessionToken":"sess.tok","expiresAt":"2026-12-01T00:00:00Z",
             "groups":[{"groupId":"g1","memberId":"m1","displayName":"Priya"}]}
            """)
        )

        await vm.signIn(identityToken: "apple.jwt", userID: "000123.abc.0001")

        XCTAssertTrue(vm.isSignedIn)
        XCTAssertEqual(vm.session?.token, "sess.tok")
        XCTAssertEqual(vm.session?.appleUserID, "000123.abc.0001")
        XCTAssertEqual(vm.groups, [GroupMembershipSummary(groupId: "g1", memberId: "m1", displayName: "Priya")])
        XCTAssertEqual(store.load()?.token, "sess.tok")
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testSignInSurfacesAFriendlyMessageOnAnUnverifiableToken() async {
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: StubTransport(statusCode: 401, json: #"{"error":{"code":"INVALID_APPLE_TOKEN","message":"nope"}}"#)
        )

        await vm.signIn(identityToken: "junk", userID: "u")

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertEqual(vm.errorMessage, "That Apple sign-in couldn't be verified. Please try again.")
    }

    @MainActor
    func testSignInSeedsTheLocalGroupStoresFromTheServerList() async {
        let identityStore = InMemoryIdentityStore()
        let knownGroups = InMemoryKnownGroupsStore()
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: StubTransport(statusCode: 200, json: """
            {"sessionToken":"s","expiresAt":"2026-12-01T00:00:00Z",
             "groups":[{"groupId":"g1","memberId":"m1","displayName":"Priya"},
                       {"groupId":"g2","memberId":"m2","displayName":"Priya"}]}
            """),
            identityStore: identityStore,
            knownGroups: knownGroups
        )

        await vm.signIn(identityToken: "apple.jwt", userID: "u")

        XCTAssertEqual(Set(knownGroups.all().map(\.groupId)), ["g1", "g2"])
        XCTAssertEqual(identityStore.identity(forGroup: "g1"), GroupIdentity(memberId: "m1", displayName: "Priya"))
        XCTAssertEqual(identityStore.identity(forGroup: "g2"), GroupIdentity(memberId: "m2", displayName: "Priya"))
    }

    @MainActor
    func testSignInDoesNotOverwriteAnExistingLocalIdentity() async {
        let identityStore = InMemoryIdentityStore()
        identityStore.setIdentity(GroupIdentity(memberId: "guest-m", displayName: "Guest Me"), forGroup: "g1")
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: StubTransport(statusCode: 200, json: """
            {"sessionToken":"s","expiresAt":"2026-12-01T00:00:00Z",
             "groups":[{"groupId":"g1","memberId":"m1","displayName":"Priya"}]}
            """),
            identityStore: identityStore
        )

        await vm.signIn(identityToken: "apple.jwt", userID: "u")

        XCTAssertEqual(identityStore.identity(forGroup: "g1")?.memberId, "guest-m")
    }

    @MainActor
    func testHandleLaunchRefreshesTheGroupListForASurvivingSession() async {
        let knownGroups = InMemoryKnownGroupsStore()
        let store = InMemorySessionStore(session(expiresIn: 20 * day))
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 200, json: #"{"groups":[{"groupId":"g9","memberId":"m9","displayName":"Sam"}]}"#),
            standing: .authorized,
            knownGroups: knownGroups
        )

        await vm.handleLaunch()

        XCTAssertEqual(vm.groups.map(\.groupId), ["g9"])
        XCTAssertEqual(knownGroups.all().map(\.groupId), ["g9"])
    }

    @MainActor
    func testSignOutClearsTheSessionEverywhere() async {
        let store = InMemorySessionStore(StoredSession(token: "t", appleUserID: "u", expiresAt: Date(timeIntervalSinceNow: day)))
        let vm = makeVM(store: store, transport: StubTransport(statusCode: 200, json: "{}"))

        vm.signOut()

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
        XCTAssertEqual(vm.groups, [])
    }

    // MARK: - handleLaunch

    @MainActor
    func testHandleLaunchWithNoStoredSessionDoesNothing() async {
        let vm = makeVM(store: InMemorySessionStore(), transport: FailingTransport())
        await vm.handleLaunch()
        XCTAssertFalse(vm.isSignedIn)
    }

    @MainActor
    func testHandleLaunchSignsOutWhenTheAppleCredentialWasRevoked() async {
        let store = InMemorySessionStore(session(expiresIn: 20 * day))
        let vm = makeVM(store: store, transport: FailingTransport(), standing: .revoked)

        await vm.handleLaunch()

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
    }

    @MainActor
    func testHandleLaunchDiscardsAnExpiredSession() async {
        let store = InMemorySessionStore(session(expiresIn: -day))
        let vm = makeVM(store: store, transport: FailingTransport(), standing: .authorized)

        await vm.handleLaunch()

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
    }

    @MainActor
    func testHandleLaunchRefreshesATokenNearingExpiry() async {
        let store = InMemorySessionStore(session(expiresIn: 3 * day, userID: "000123.abc.0001"))
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 200, json: #"{"sessionToken":"fresh.tok","expiresAt":"2027-01-01T00:00:00Z"}"#),
            standing: .authorized
        )

        await vm.handleLaunch()

        XCTAssertEqual(vm.session?.token, "fresh.tok")
        XCTAssertEqual(vm.session?.appleUserID, "000123.abc.0001", "the Apple user id must survive a refresh")
        XCTAssertEqual(store.load()?.token, "fresh.tok")
    }

    @MainActor
    func testHandleLaunchKeepsTheSessionWhenARefreshFailsTransiently() async {
        let original = session(expiresIn: 3 * day)
        let store = InMemorySessionStore(original)
        let vm = makeVM(store: store, transport: FailingTransport(), standing: .authorized)

        await vm.handleLaunch()

        XCTAssertEqual(vm.session, original)
        XCTAssertEqual(store.load(), original)
    }

    @MainActor
    func testHandleLaunchSignsOutWhenRefreshReportsAnInvalidSession() async {
        let store = InMemorySessionStore(session(expiresIn: 3 * day))
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 401, json: #"{"error":{"code":"INVALID_SESSION","message":"gone"}}"#),
            standing: .authorized
        )

        await vm.handleLaunch()

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
    }

    // MARK: - helpers

    private let day: TimeInterval = 24 * 60 * 60

    private func session(expiresIn seconds: TimeInterval, userID: String = "u") -> StoredSession {
        StoredSession(token: "stored.tok", appleUserID: userID, expiresAt: Date(timeIntervalSinceNow: seconds))
    }

    @MainActor
    private func makeVM(
        store: SessionStoring,
        transport: ClanTabTransport,
        standing: CredentialStanding = .authorized,
        identityStore: IdentityStoring = InMemoryIdentityStore(),
        knownGroups: KnownGroupsStoring = InMemoryKnownGroupsStore()
    ) -> AuthViewModel {
        AuthViewModel(
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: transport),
            sessionStore: store,
            identityStore: identityStore,
            knownGroups: knownGroups,
            credentialStanding: { _ in standing }
        )
    }
}

private struct StubTransport: ClanTabTransport {
    let statusCode: Int
    let json: String
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        (Data(json.utf8), statusCode)
    }
}

/// Always throws — stands in for "no network".
private struct FailingTransport: ClanTabTransport {
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        throw URLError(.notConnectedToInternet)
    }
}
