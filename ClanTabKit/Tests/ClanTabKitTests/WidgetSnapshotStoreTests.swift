import Testing
import Foundation
@testable import ClanTabKit

@Suite("WidgetSnapshotStore")
struct WidgetSnapshotStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func sample(_ groupId: String = "g1") -> WidgetSnapshot {
        WidgetSnapshot(
            groupId: groupId,
            groupName: "Flatmates",
            balances: [Balance(memberId: "m1", currency: "INR", netMinor: -5000)],
            updatedAt: t0
        )
    }

    @Test("starts empty, saves, and overwrites on the next save")
    func testInMemoryStore() {
        let store = InMemoryWidgetSnapshotStore()
        #expect(store.snapshot() == nil)

        store.save(sample())
        #expect(store.snapshot() == sample())

        let updated = WidgetSnapshot(groupId: "g2", groupName: "Trip", balances: [], updatedAt: t0.addingTimeInterval(60))
        store.save(updated)
        #expect(store.snapshot() == updated)
    }

    @Test("clear removes the snapshot")
    func testClear() {
        let store = InMemoryWidgetSnapshotStore(sample())
        store.clear()
        #expect(store.snapshot() == nil)
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsWidgetSnapshotStore(defaults: defaults)
        #expect(store.snapshot() == nil)

        store.save(sample())

        let reloaded = UserDefaultsWidgetSnapshotStore(defaults: defaults)
        #expect(reloaded.snapshot() == sample())

        reloaded.clear()
        #expect(reloaded.snapshot() == nil)
        #expect(store.snapshot() == nil) // same backing suite
    }
}
