import Testing
import Foundation
@testable import ClanTabKit

@Suite("RemindHistory")
struct RemindHistoryTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    // MARK: - isInCooldown

    @Test("never reminded is never in cooldown")
    func testNeverRemindedNotInCooldown() {
        #expect(RemindHistory.isInCooldown(lastRemindedAt: nil, now: t0) == false)
    }

    @Test("just reminded is in cooldown")
    func testJustRemindedInCooldown() {
        #expect(RemindHistory.isInCooldown(lastRemindedAt: t0, now: t0.addingTimeInterval(60)) == true)
    }

    @Test("right at the cooldown boundary is no longer in cooldown")
    func testCooldownBoundary() {
        let now = t0.addingTimeInterval(RemindHistory.cooldown)
        #expect(RemindHistory.isInCooldown(lastRemindedAt: t0, now: now) == false)
        #expect(RemindHistory.isInCooldown(lastRemindedAt: t0, now: now.addingTimeInterval(-1)) == true)
    }

    // MARK: - relativeLabel

    @Test("relativeLabel", arguments: [
        (TimeInterval(0), "Just now"), (TimeInterval(30), "Just now"),
        (TimeInterval(5 * 60), "5m ago"), (TimeInterval(59 * 60), "59m ago"),
        (TimeInterval(2 * 3600), "2h ago"), (TimeInterval(23 * 3600), "23h ago"),
        (TimeInterval(3 * 86_400), "3d ago"),
    ])
    func testRelativeLabel(elapsed: TimeInterval, expected: String) {
        #expect(RemindHistory.relativeLabel(since: t0, now: t0.addingTimeInterval(elapsed)) == expected)
    }

    @Test("clock skew (a 'reminded' time in the future) floors at Just now, not a negative duration")
    func testClockSkewFloors() {
        #expect(RemindHistory.relativeLabel(since: t0.addingTimeInterval(60), now: t0) == "Just now")
    }
}

@Suite("RemindHistoryStore")
struct RemindHistoryStoreTests {
    @Test("in-memory store round-trips a map")
    func testInMemoryRoundTrip() {
        let date = Date(timeIntervalSince1970: 500_000)
        let store = InMemoryRemindHistoryStore()
        #expect(store.load() == [:])
        store.save(["a-b-INR": date])
        #expect(store.load() == ["a-b-INR": date])
    }

    @Test("UserDefaults store round-trips through encode/decode and clears on an empty save")
    func testUserDefaultsRoundTrip() {
        let defaults = UserDefaults(suiteName: "RemindHistoryStoreTests.\(UUID().uuidString)")!
        let store = UserDefaultsRemindHistoryStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 500_000)
        #expect(store.load() == [:])
        store.save(["a-b-INR": date])
        #expect(store.load() == ["a-b-INR": date])
        store.save([:])
        #expect(store.load() == [:])
    }
}
