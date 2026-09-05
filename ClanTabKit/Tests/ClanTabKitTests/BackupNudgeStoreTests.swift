import Testing
import Foundation
@testable import ClanTabKit

@Suite("BackupNudge")
struct BackupNudgeTests {
    private let firstLaunch = Date(timeIntervalSince1970: 1_000_000)

    @Test("never shows before firstLaunchAt is known")
    func testNoFirstLaunch() {
        #expect(BackupNudge.shouldShow(now: firstLaunch, lastShownAt: nil, firstLaunchAt: nil) == false)
    }

    @Test("stays quiet during the first week")
    func testMinimumAccountAge() {
        let sixDaysIn = firstLaunch.addingTimeInterval(6 * 24 * 60 * 60)
        #expect(BackupNudge.shouldShow(now: sixDaysIn, lastShownAt: nil, firstLaunchAt: firstLaunch) == false)

        let sevenDaysIn = firstLaunch.addingTimeInterval(7 * 24 * 60 * 60)
        #expect(BackupNudge.shouldShow(now: sevenDaysIn, lastShownAt: nil, firstLaunchAt: firstLaunch) == true)
    }

    @Test("re-shows only after the interval since it was last shown")
    func testRecurs() {
        let shownAt = firstLaunch.addingTimeInterval(30 * 24 * 60 * 60)
        let tooSoon = shownAt.addingTimeInterval(29 * 24 * 60 * 60)
        #expect(BackupNudge.shouldShow(now: tooSoon, lastShownAt: shownAt, firstLaunchAt: firstLaunch) == false)

        let dueAgain = shownAt.addingTimeInterval(30 * 24 * 60 * 60)
        #expect(BackupNudge.shouldShow(now: dueAgain, lastShownAt: shownAt, firstLaunchAt: firstLaunch) == true)
    }
}

@Suite("BackupNudgeStore")
struct BackupNudgeStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("starts with no last-shown time, records it, and updates on every call")
    func testInMemoryStore() {
        let store = InMemoryBackupNudgeStore()
        #expect(store.lastShownAt() == nil)

        store.recordShown(t0)
        #expect(store.lastShownAt() == t0)

        let t1 = t0.addingTimeInterval(1)
        store.recordShown(t1)
        #expect(store.lastShownAt() == t1)
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsBackupNudgeStore(defaults: defaults)
        #expect(store.lastShownAt() == nil)

        store.recordShown(t0)

        let reloaded = UserDefaultsBackupNudgeStore(defaults: defaults)
        #expect(reloaded.lastShownAt()?.timeIntervalSince1970 == t0.timeIntervalSince1970)
    }
}
