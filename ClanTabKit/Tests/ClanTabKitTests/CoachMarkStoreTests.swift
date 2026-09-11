import Foundation
import Testing
@testable import ClanTabKit

@Suite("CoachMarkStore")
struct CoachMarkStoreTests {
    @Test("in-memory: unseen until marked, per id, then sticky")
    func testInMemory() {
        let store = InMemoryCoachMarkStore()
        #expect(!store.hasSeen("tip.a"))
        #expect(!store.hasSeen("tip.b"))

        store.markSeen("tip.a")
        #expect(store.hasSeen("tip.a"))
        #expect(!store.hasSeen("tip.b")) // independent of tip.a

        store.markSeen("tip.a") // idempotent
        #expect(store.hasSeen("tip.a"))
    }

    @Test("in-memory: honours an initial seeded set")
    func testInMemorySeeded() {
        let store = InMemoryCoachMarkStore(seen: ["tip.a"])
        #expect(store.hasSeen("tip.a"))
        #expect(!store.hasSeen("tip.b"))
    }

    @Test("in-memory: resetAll clears every tip — Settings 'Show tips again'")
    func testInMemoryResetAll() {
        let store = InMemoryCoachMarkStore(seen: ["tip.a", "tip.b"])
        store.resetAll()
        #expect(!store.hasSeen("tip.a"))
        #expect(!store.hasSeen("tip.b"))
    }

    @Test("UserDefaults-backed: unseen by default, persists per id across instances, resetAll clears all")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.a"))

        UserDefaultsCoachMarkStore(defaults: defaults).markSeen("tip.a")
        #expect(UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.a"))
        #expect(!UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.b"))

        UserDefaultsCoachMarkStore(defaults: defaults).markSeen("tip.b")
        #expect(UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.a"))
        #expect(UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.b"))

        UserDefaultsCoachMarkStore(defaults: defaults).resetAll()
        #expect(!UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.a"))
        #expect(!UserDefaultsCoachMarkStore(defaults: defaults).hasSeen("tip.b"))
    }
}
