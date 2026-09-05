import Testing
import Foundation
@testable import ClanTabKit

@Suite("SessionStore")
struct SessionStoreTests {
    private func session(expiresAt: Date) -> StoredSession {
        StoredSession(token: "t.o.k", provider: .apple, appleUserID: "000123.abc.0001", expiresAt: expiresAt)
    }

    @Test("InMemorySessionStore round-trips and clears")
    func testInMemoryRoundTrip() {
        let store = InMemorySessionStore()
        #expect(store.load() == nil)

        let s = session(expiresAt: Date(timeIntervalSinceNow: 3600))
        store.save(s)
        #expect(store.load() == s)

        store.clear()
        #expect(store.load() == nil)
    }

    @Test("InMemorySessionStore can be seeded")
    func testSeeded() {
        let s = session(expiresAt: Date(timeIntervalSinceNow: 3600))
        #expect(InMemorySessionStore(s).load() == s)
    }

    @Test("isExpired is true only once the expiry has passed")
    func testIsExpired() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        #expect(session(expiresAt: now.addingTimeInterval(1)).isExpired(now: now) == false)
        #expect(session(expiresAt: now).isExpired(now: now) == true)
        #expect(session(expiresAt: now.addingTimeInterval(-1)).isExpired(now: now) == true)
    }

    @Test("needsRefresh fires inside the 7-day window, not before")
    func testNeedsRefresh() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let day: TimeInterval = 24 * 60 * 60
        #expect(session(expiresAt: now.addingTimeInterval(30 * day)).needsRefresh(now: now) == false)
        #expect(session(expiresAt: now.addingTimeInterval(8 * day)).needsRefresh(now: now) == false)
        #expect(session(expiresAt: now.addingTimeInterval(6 * day)).needsRefresh(now: now) == true)
        #expect(session(expiresAt: now.addingTimeInterval(-day)).needsRefresh(now: now) == true)
    }

    @Test("StoredSession is Codable")
    func testCodable() throws {
        let s = session(expiresAt: Date(timeIntervalSince1970: 1_700_000_000))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(StoredSession.self, from: data) == s)
    }
}
