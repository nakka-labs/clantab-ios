import Testing
import Foundation
@testable import ClanTabKit

@Suite("DashboardReconcile")
struct DashboardReconcileTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("reconciles when it has never run")
    func testNeverRun() {
        #expect(DashboardReconcile.shouldReconcile(lastAt: nil, now: now))
    }

    @Test("skips a recent reconcile")
    func testRecent() {
        let lastAt = now.addingTimeInterval(-DashboardReconcile.staleAfter + 60)
        #expect(!DashboardReconcile.shouldReconcile(lastAt: lastAt, now: now))
    }

    @Test("reconciles once the last run is stale")
    func testStale() {
        let lastAt = now.addingTimeInterval(-DashboardReconcile.staleAfter - 1)
        #expect(DashboardReconcile.shouldReconcile(lastAt: lastAt, now: now))
    }

    @Test("the staleness boundary reconciles")
    func testBoundary() {
        let lastAt = now.addingTimeInterval(-DashboardReconcile.staleAfter)
        #expect(DashboardReconcile.shouldReconcile(lastAt: lastAt, now: now))
    }
}

@Suite("DashboardSyncStore")
struct DashboardSyncStoreTests {
    @Test("InMemory round-trips the timestamp")
    func testInMemory() {
        let store = InMemoryDashboardSyncStore()
        #expect(store.lastReconcileAt() == nil)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        store.recordReconcile(t)
        #expect(store.lastReconcileAt() == t)
    }

    @Test("UserDefaults-backed store persists across instances")
    func testUserDefaults() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        UserDefaultsDashboardSyncStore(defaults: defaults).recordReconcile(t)
        #expect(UserDefaultsDashboardSyncStore(defaults: defaults).lastReconcileAt() == t)
    }
}
