import Testing
import Foundation
@testable import ClanTabKit

@Suite("SyncNudgeStore")
struct SyncNudgeStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    @Test("recordFirstLaunch sets the time once and never moves it")
    func testRecordOnce() {
        let store = InMemorySyncNudgeStore()
        #expect(store.firstLaunchAt() == nil)

        store.recordFirstLaunch(t0)
        #expect(store.firstLaunchAt() == t0)

        store.recordFirstLaunch(t0.addingTimeInterval(9999))
        #expect(store.firstLaunchAt() == t0)
    }

    @Test("dismiss flips isDismissed and sticks")
    func testDismiss() {
        let store = InMemorySyncNudgeStore(firstLaunchAt: t0)
        #expect(store.isDismissed() == false)
        store.dismiss()
        #expect(store.isDismissed() == true)
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsSyncNudgeStore(defaults: defaults)
        #expect(store.firstLaunchAt() == nil)
        #expect(store.isDismissed() == false)

        store.recordFirstLaunch(t0)
        store.dismiss()

        let reloaded = UserDefaultsSyncNudgeStore(defaults: defaults)
        #expect(reloaded.firstLaunchAt()?.timeIntervalSince1970 == t0.timeIntervalSince1970)
        #expect(reloaded.isDismissed() == true)

        reloaded.recordFirstLaunch(t0.addingTimeInterval(9999))
        #expect(reloaded.firstLaunchAt()?.timeIntervalSince1970 == t0.timeIntervalSince1970)
    }
}
