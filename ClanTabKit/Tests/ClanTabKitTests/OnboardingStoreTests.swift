import Foundation
import Testing
@testable import ClanTabKit

@Suite("OnboardingStore")
struct OnboardingStoreTests {
    @Test("in-memory: false until marked, then sticky")
    func testInMemory() {
        let store = InMemoryOnboardingStore()
        #expect(!store.hasCompletedOnboarding())
        store.markOnboardingComplete()
        #expect(store.hasCompletedOnboarding())
        store.markOnboardingComplete() // idempotent
        #expect(store.hasCompletedOnboarding())
    }

    @Test("in-memory: honours an initial completed value")
    func testInMemorySeeded() {
        #expect(InMemoryOnboardingStore(completed: true).hasCompletedOnboarding())
    }

    @Test("in-memory: reset clears a completed flag — Settings 'Show tips again'")
    func testInMemoryReset() {
        let store = InMemoryOnboardingStore(completed: true)
        store.reset()
        #expect(!store.hasCompletedOnboarding())
    }

    @Test("UserDefaults-backed: defaults false, persists true across instances")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!UserDefaultsOnboardingStore(defaults: defaults).hasCompletedOnboarding())

        UserDefaultsOnboardingStore(defaults: defaults).markOnboardingComplete()

        #expect(UserDefaultsOnboardingStore(defaults: defaults).hasCompletedOnboarding())

        UserDefaultsOnboardingStore(defaults: defaults).reset()
        #expect(!UserDefaultsOnboardingStore(defaults: defaults).hasCompletedOnboarding())
    }
}
