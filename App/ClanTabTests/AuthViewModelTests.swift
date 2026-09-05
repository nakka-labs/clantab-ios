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
        let store = InMemorySessionStore(StoredSession(token: "t", provider: .apple, appleUserID: "u", expiresAt: Date(timeIntervalSinceNow: day)))
        let vm = makeVM(store: store, transport: StubTransport(statusCode: 200, json: "{}"))

        vm.signOut()

        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
        XCTAssertEqual(vm.groups, [])
    }

    // MARK: - sync nudge (ACCOUNTS_DESIGN.md §10)

    @MainActor
    func testSyncNudgeHiddenBeforeTheThresholds() async {
        let firstLaunch = Date(timeIntervalSince1970: 1_000_000)
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: FailingTransport(),
            knownGroups: InMemoryKnownGroupsStore([known("g1", at: firstLaunch)]),
            syncNudge: InMemorySyncNudgeStore(firstLaunchAt: firstLaunch)
        )
        // One group, one day in.
        XCTAssertFalse(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(day)))
    }

    @MainActor
    func testSyncNudgeShownAtTheSecondGroup() async {
        let firstLaunch = Date(timeIntervalSince1970: 1_000_000)
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: FailingTransport(),
            knownGroups: InMemoryKnownGroupsStore([known("g1", at: firstLaunch), known("g2", at: firstLaunch)]),
            syncNudge: InMemorySyncNudgeStore(firstLaunchAt: firstLaunch)
        )
        XCTAssertTrue(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(day)))
    }

    @MainActor
    func testSyncNudgeShownAfterSevenDaysWithOneGroup() async {
        let firstLaunch = Date(timeIntervalSince1970: 1_000_000)
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: FailingTransport(),
            knownGroups: InMemoryKnownGroupsStore([known("g1", at: firstLaunch)]),
            syncNudge: InMemorySyncNudgeStore(firstLaunchAt: firstLaunch)
        )
        XCTAssertFalse(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(6 * day)))
        XCTAssertTrue(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(7 * day)))
    }

    @MainActor
    func testSyncNudgeNeverShownOnceDismissed() async {
        let firstLaunch = Date(timeIntervalSince1970: 1_000_000)
        let nudge = InMemorySyncNudgeStore(firstLaunchAt: firstLaunch)
        let vm = makeVM(
            store: InMemorySessionStore(),
            transport: FailingTransport(),
            knownGroups: InMemoryKnownGroupsStore([known("g1", at: firstLaunch), known("g2", at: firstLaunch)]),
            syncNudge: nudge
        )
        XCTAssertTrue(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(day)))

        vm.dismissSyncNudge()

        XCTAssertFalse(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(day)))
        XCTAssertTrue(nudge.isDismissed())
    }

    @MainActor
    func testSyncNudgeNeverShownWhenSignedIn() async {
        let firstLaunch = Date(timeIntervalSince1970: 1_000_000)
        let vm = makeVM(
            store: InMemorySessionStore(session(expiresIn: 20 * day)),
            transport: FailingTransport(),
            knownGroups: InMemoryKnownGroupsStore([known("g1", at: firstLaunch), known("g2", at: firstLaunch)]),
            syncNudge: InMemorySyncNudgeStore(firstLaunchAt: firstLaunch)
        )
        XCTAssertTrue(vm.isSignedIn)
        XCTAssertFalse(vm.shouldShowSyncNudge(now: firstLaunch.addingTimeInterval(30 * day)))
    }

    @MainActor
    func testHandleLaunchRecordsFirstLaunchOnce() async {
        let nudge = InMemorySyncNudgeStore()
        let vm = makeVM(store: InMemorySessionStore(), transport: FailingTransport(), syncNudge: nudge)

        await vm.handleLaunch()
        let recorded = nudge.firstLaunchAt()
        XCTAssertNotNil(recorded)

        await vm.handleLaunch()
        XCTAssertEqual(nudge.firstLaunchAt(), recorded, "first-launch time must not move on later launches")
    }

    // MARK: - claim

    @MainActor
    func testClaimSeedsTheIdentityAndRefreshesTheGroupList() async {
        let identityStore = InMemoryIdentityStore()
        let knownGroups = InMemoryKnownGroupsStore()
        let vm = makeVM(
            store: InMemorySessionStore(session(expiresIn: 20 * day)),
            transport: RoutingTransport(responses: [
                "/claim": (200, #"{"member":{"id":"m1","displayName":"Priya"}}"#),
                "/api/auth/groups": (200, #"{"groups":[{"groupId":"g1","memberId":"m1","displayName":"Priya"}]}"#),
            ]),
            identityStore: identityStore,
            knownGroups: knownGroups
        )

        let ok = await vm.claim(groupId: "g1", memberId: "m1")

        XCTAssertTrue(ok)
        XCTAssertEqual(identityStore.identity(forGroup: "g1"), GroupIdentity(memberId: "m1", displayName: "Priya"))
        XCTAssertEqual(knownGroups.all().map(\.groupId), ["g1"])
        XCTAssertEqual(vm.groups.map(\.groupId), ["g1"])
        XCTAssertNil(vm.errorMessage)
    }

    @MainActor
    func testClaimFailureSurfacesTheServerMessageAndSeedsNothing() async {
        let identityStore = InMemoryIdentityStore()
        let vm = makeVM(
            store: InMemorySessionStore(session(expiresIn: 20 * day)),
            transport: StubTransport(statusCode: 409, json: #"{"error":{"code":"ALREADY_CLAIMED","message":"Linked to another account."}}"#),
            identityStore: identityStore
        )

        let ok = await vm.claim(groupId: "g1", memberId: "m1")

        XCTAssertFalse(ok)
        XCTAssertEqual(vm.errorMessage, "Linked to another account.")
        XCTAssertNil(identityStore.identity(forGroup: "g1"))
    }

    @MainActor
    func testClaimWithNoSessionIsANoOp() async {
        let vm = makeVM(store: InMemorySessionStore(), transport: FailingTransport())
        let ok = await vm.claim(groupId: "g1", memberId: "m1")
        XCTAssertFalse(ok)
    }

    // MARK: - deleteAccount (ACCOUNTS_DESIGN.md §11)

    @MainActor
    func testDeleteAccountClearsTheSessionOnSuccess() async {
        let store = InMemorySessionStore(session(expiresIn: 20 * day))
        let vm = makeVM(store: store, transport: StubTransport(statusCode: 204, json: ""))

        let ok = await vm.deleteAccount()

        XCTAssertTrue(ok)
        XCTAssertFalse(vm.isSignedIn)
        XCTAssertNil(store.load())
    }

    @MainActor
    func testDeleteAccountKeepsTheSessionOnAServerError() async {
        let store = InMemorySessionStore(session(expiresIn: 20 * day))
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 500, json: #"{"error":{"code":"INTERNAL","message":"boom"}}"#)
        )

        let ok = await vm.deleteAccount()

        XCTAssertFalse(ok)
        XCTAssertTrue(vm.isSignedIn)
        XCTAssertNotNil(vm.errorMessage)
    }

    @MainActor
    func testDeleteAccountTreatsAnInvalidSessionAsAlreadyDone() async {
        let store = InMemorySessionStore(session(expiresIn: 20 * day))
        let vm = makeVM(
            store: store,
            transport: StubTransport(statusCode: 401, json: #"{"error":{"code":"INVALID_SESSION","message":"gone"}}"#)
        )

        let ok = await vm.deleteAccount()

        XCTAssertTrue(ok)
        XCTAssertFalse(vm.isSignedIn)
    }

    @MainActor
    func testDeleteAccountWithNoSessionIsANoOp() async {
        let vm = makeVM(store: InMemorySessionStore(), transport: FailingTransport())
        let ok = await vm.deleteAccount()
        XCTAssertFalse(ok)
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
        StoredSession(token: "stored.tok", provider: .apple, appleUserID: userID, expiresAt: Date(timeIntervalSinceNow: seconds))
    }

    private func known(_ groupId: String, at date: Date) -> KnownGroup {
        KnownGroup(groupId: groupId, name: groupId, lastOpenedAt: date)
    }

    @MainActor
    private func makeVM(
        store: SessionStoring,
        transport: ClanTabTransport,
        standing: CredentialStanding = .authorized,
        identityStore: IdentityStoring = InMemoryIdentityStore(),
        knownGroups: KnownGroupsStoring = InMemoryKnownGroupsStore(),
        syncNudge: SyncNudgeStoring = InMemorySyncNudgeStore()
    ) -> AuthViewModel {
        AuthViewModel(
            client: ClanTabClient(baseURL: URL(string: "https://example.invalid/")!, transport: transport),
            sessionStore: store,
            identityStore: identityStore,
            knownGroups: knownGroups,
            syncNudge: syncNudge,
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

/// Routes canned responses by a path substring — for flows that make more than
/// one call (claim → then myGroups).
private struct RoutingTransport: ClanTabTransport {
    let responses: [String: (Int, String)]
    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        let path = request.url?.path ?? ""
        for (key, value) in responses where path.contains(key) {
            return (Data(value.1.utf8), value.0)
        }
        return (Data(), 404)
    }
}
