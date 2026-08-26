import Testing
import Foundation
@testable import SquareKit

@Suite("IdentityStore")
struct IdentityStoreTests {
    @Test("InMemoryIdentityStore round-trips an identity per group")
    func testInMemoryRoundTrip() {
        let store = InMemoryIdentityStore()
        #expect(store.identity(forGroup: "g1") == nil)

        let identity = GroupIdentity(memberId: "m1", displayName: "Alice")
        store.setIdentity(identity, forGroup: "g1")
        #expect(store.identity(forGroup: "g1") == identity)

        store.removeIdentity(forGroup: "g1")
        #expect(store.identity(forGroup: "g1") == nil)
    }

    @Test("InMemoryIdentityStore keeps identities for different groups independent")
    func testInMemoryIsolatedPerGroup() {
        let store = InMemoryIdentityStore()
        store.setIdentity(GroupIdentity(memberId: "m1", displayName: "Alice"), forGroup: "g1")
        store.setIdentity(GroupIdentity(memberId: "m2", displayName: "Bob"), forGroup: "g2")

        #expect(store.identity(forGroup: "g1")?.displayName == "Alice")
        #expect(store.identity(forGroup: "g2")?.displayName == "Bob")
    }

    @Test("UserDefaultsIdentityStore round-trips an identity through a real UserDefaults suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.squarely.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsIdentityStore(defaults: defaults)
        #expect(store.identity(forGroup: "g1") == nil)

        let identity = GroupIdentity(memberId: "m1", displayName: "Alice")
        store.setIdentity(identity, forGroup: "g1")
        #expect(store.identity(forGroup: "g1") == identity)

        store.removeIdentity(forGroup: "g1")
        #expect(store.identity(forGroup: "g1") == nil)
    }

    @Test("UserDefaultsIdentityStore namespaces keys so groups never collide")
    func testUserDefaultsNamespacing() throws {
        let suiteName = "com.squarely.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsIdentityStore(defaults: defaults)
        store.setIdentity(GroupIdentity(memberId: "m1", displayName: "Alice"), forGroup: "g1")
        store.setIdentity(GroupIdentity(memberId: "m2", displayName: "Bob"), forGroup: "g2")

        #expect(store.identity(forGroup: "g1")?.displayName == "Alice")
        #expect(store.identity(forGroup: "g2")?.displayName == "Bob")
    }
}
