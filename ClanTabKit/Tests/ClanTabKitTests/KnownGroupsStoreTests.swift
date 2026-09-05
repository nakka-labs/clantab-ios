import Testing
import Foundation
@testable import ClanTabKit

@Suite("KnownGroupsStore")
struct KnownGroupsStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("remember inserts, then returns groups most-recently-opened first")
    func testInsertAndOrder() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        store.remember(groupId: "g2", name: "Flatmates", at: t0.addingTimeInterval(60))

        #expect(store.all().map(\.groupId) == ["g2", "g1"])
    }

    @Test("remember on an existing group bumps its recency")
    func testBumpRecency() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        store.remember(groupId: "g2", name: "Flatmates", at: t0.addingTimeInterval(60))
        store.remember(groupId: "g1", name: nil, at: t0.addingTimeInterval(120))

        #expect(store.all().map(\.groupId) == ["g1", "g2"])
    }

    @Test("a non-empty name fills a blank one; nil never clobbers a cached name")
    func testNameMerge() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: nil, at: t0)          // join — no name yet
        #expect(store.all().first?.name == "")

        store.remember(groupId: "g1", name: "Goa Trip", at: t0)   // group state loaded
        #expect(store.all().first?.name == "Goa Trip")

        store.remember(groupId: "g1", name: nil, at: t0)          // re-open, still no name passed
        #expect(store.all().first?.name == "Goa Trip")

        store.remember(groupId: "g1", name: "", at: t0)           // empty must not clobber
        #expect(store.all().first?.name == "Goa Trip")
    }

    @Test("forget removes one group")
    func testForget() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "A", at: t0)
        store.remember(groupId: "g2", name: "B", at: t0)

        store.forget(groupId: "g1")
        #expect(store.all().map(\.groupId) == ["g2"])
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsKnownGroupsStore(defaults: defaults)
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        store.remember(groupId: "g2", name: nil, at: t0.addingTimeInterval(30))

        let reloaded = UserDefaultsKnownGroupsStore(defaults: defaults)
        #expect(reloaded.all().map(\.groupId) == ["g2", "g1"])
        #expect(reloaded.all().first(where: { $0.groupId == "g1" })?.name == "Goa Trip")

        reloaded.forget(groupId: "g2")
        #expect(UserDefaultsKnownGroupsStore(defaults: defaults).all().map(\.groupId) == ["g1"])
    }

    @Test("the convenience overload defaults name to nil and the timestamp to now")
    func testConvenienceOverload() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1")
        #expect(store.all().map(\.groupId) == ["g1"])
        #expect(store.all().first?.name == "")
    }

    // MARK: - accessToken (ACCESS_TOKEN_PLAN.md)

    @Test("remember sets accessToken on insert, and a later nil doesn't clobber it")
    func testAccessTokenPersistsAndIsntClobbered() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", accessToken: "tok1", at: t0)
        #expect(store.all().first?.accessToken == "tok1")

        // A later remember with no token (e.g. mirroring GET /api/auth/groups,
        // which doesn't return one) leaves the stored token alone.
        store.remember(groupId: "g1", accessToken: nil, at: t0.addingTimeInterval(60))
        #expect(store.all().first?.accessToken == "tok1")

        // A non-nil token (e.g. after a Regenerate Link) does update it.
        store.remember(groupId: "g1", accessToken: "tok2", at: t0.addingTimeInterval(120))
        #expect(store.all().first?.accessToken == "tok2")
    }

    // MARK: - myBalances (FEATURE_BACKLOG.md — groups list balance summary)

    @Test("a freshly-remembered group has no balances yet")
    func testMyBalancesNilUntilFetched() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        #expect(store.all().first?.myBalances == nil)
    }

    @Test("updateBalances sets the balance summary without touching lastOpenedAt")
    func testUpdateBalances() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)

        store.updateBalances(groupId: "g1", myBalances: [Balance(memberId: "m1", currency: "INR", netMinor: -500)])

        let group = store.all().first
        #expect(group?.myBalances == [Balance(memberId: "m1", currency: "INR", netMinor: -500)])
        #expect(group?.lastOpenedAt == t0) // unaffected — see updateBalances' doc comment
    }

    @Test("updateBalances can set an empty array — confirmed settled, distinct from nil (never fetched)")
    func testUpdateBalancesSettled() {
        let store = InMemoryKnownGroupsStore()
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        store.updateBalances(groupId: "g1", myBalances: [])
        #expect(store.all().first?.myBalances == [])
    }

    @Test("updateBalances is a no-op for an unknown group")
    func testUpdateBalancesUnknownGroup() {
        let store = InMemoryKnownGroupsStore()
        store.updateBalances(groupId: "ghost", myBalances: [Balance(memberId: "m1", currency: "INR", netMinor: 100)])
        #expect(store.all().isEmpty)
    }

    @Test("UserDefaults-backed store round-trips myBalances too")
    func testUserDefaultsRoundTripsBalances() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsKnownGroupsStore(defaults: defaults)
        store.remember(groupId: "g1", name: "Goa Trip", at: t0)
        store.updateBalances(groupId: "g1", myBalances: [Balance(memberId: "m1", currency: "INR", netMinor: 250)])

        let reloaded = UserDefaultsKnownGroupsStore(defaults: defaults)
        #expect(reloaded.all().first?.myBalances == [Balance(memberId: "m1", currency: "INR", netMinor: 250)])
    }
}
