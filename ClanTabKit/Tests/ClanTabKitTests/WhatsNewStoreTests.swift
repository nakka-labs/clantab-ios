import Foundation
import Testing
@testable import ClanTabKit

@Suite("WhatsNewStore")
struct WhatsNewStoreTests {
    @Test("in-memory: nil until marked, then sticky")
    func testInMemory() {
        let store = InMemoryWhatsNewStore()
        #expect(store.lastSeenBuild() == nil)
        store.markSeen(build: 8)
        #expect(store.lastSeenBuild() == 8)
        store.markSeen(build: 9) // keeps advancing
        #expect(store.lastSeenBuild() == 9)
    }

    @Test("in-memory: honours an initial seeded value")
    func testInMemorySeeded() {
        #expect(InMemoryWhatsNewStore(lastSeenBuild: 3).lastSeenBuild() == 3)
    }

    @Test("UserDefaults-backed: nil by default, persists across instances, distinguishes nil from 0")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(UserDefaultsWhatsNewStore(defaults: defaults).lastSeenBuild() == nil)

        UserDefaultsWhatsNewStore(defaults: defaults).markSeen(build: 0)
        #expect(UserDefaultsWhatsNewStore(defaults: defaults).lastSeenBuild() == 0)

        UserDefaultsWhatsNewStore(defaults: defaults).markSeen(build: 7)
        #expect(UserDefaultsWhatsNewStore(defaults: defaults).lastSeenBuild() == 7)
    }
}
