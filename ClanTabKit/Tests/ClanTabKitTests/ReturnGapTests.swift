import Testing
import Foundation
@testable import ClanTabKit

@Suite("ReturnGap")
struct ReturnGapTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("never shows for a fresh install / pre-feature user (nil lastOpenAt)")
    func testNilLastOpen() {
        #expect(ReturnGap.shouldShowWelcomeBack(now: t0, lastOpenAt: nil) == false)
    }

    @Test("stays quiet under the gap threshold")
    func testUnderThreshold() {
        let twoDaysLater = t0.addingTimeInterval(2 * 24 * 60 * 60)
        #expect(ReturnGap.shouldShowWelcomeBack(now: twoDaysLater, lastOpenAt: t0) == false)
    }

    @Test("shows once the gap reaches the threshold")
    func testAtThreshold() {
        let threeDaysLater = t0.addingTimeInterval(3 * 24 * 60 * 60)
        #expect(ReturnGap.shouldShowWelcomeBack(now: threeDaysLater, lastOpenAt: t0) == true)
    }

    @Test("shows well past the threshold too")
    func testWellPastThreshold() {
        let twoWeeksLater = t0.addingTimeInterval(14 * 24 * 60 * 60)
        #expect(ReturnGap.shouldShowWelcomeBack(now: twoWeeksLater, lastOpenAt: t0) == true)
    }
}

@Suite("ReturnGapStore")
struct ReturnGapStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("in-memory: starts with no last-open time, records it, and keeps advancing")
    func testInMemoryStore() {
        let store = InMemoryReturnGapStore()
        #expect(store.lastOpenAt() == nil)

        store.recordOpen(t0)
        #expect(store.lastOpenAt() == t0)

        let t1 = t0.addingTimeInterval(1)
        store.recordOpen(t1)
        #expect(store.lastOpenAt() == t1)
    }

    @Test("in-memory: honours an initial seeded value")
    func testInMemorySeeded() {
        #expect(InMemoryReturnGapStore(lastOpenAt: t0).lastOpenAt() == t0)
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsReturnGapStore(defaults: defaults)
        #expect(store.lastOpenAt() == nil)

        store.recordOpen(t0)

        let reloaded = UserDefaultsReturnGapStore(defaults: defaults)
        #expect(reloaded.lastOpenAt()?.timeIntervalSince1970 == t0.timeIntervalSince1970)
    }
}
