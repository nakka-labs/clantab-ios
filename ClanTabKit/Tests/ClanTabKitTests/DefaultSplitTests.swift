import Foundation
import Testing
@testable import ClanTabKit

@Suite("DefaultSplit")
struct DefaultSplitTests {
    private let ana = Member(id: "a", displayName: "Ana")
    private let ben = Member(id: "b", displayName: "Ben")
    private let cara = Member(id: "c", displayName: "Cara")

    private func split(_ pairs: (String, Int)...) -> DefaultSplit {
        DefaultSplit(weights: pairs.map { DefaultSplitWeight(memberId: $0.0, weight: $0.1) })
    }

    @Test("isValid needs positive weights, distinct members, summing to 100")
    func testIsValid() {
        #expect(split(("a", 60), ("b", 40)).isValid)
        #expect(split(("a", 100)).isValid)
        #expect(!split(("a", 60), ("b", 30)).isValid)       // sums to 90
        #expect(!split(("a", 50), ("b", 50), ("c", 0)).isValid) // zero weight
        #expect(!split(("a", 50), ("a", 50)).isValid)        // duplicate member
        #expect(!DefaultSplit(weights: []).isValid)          // empty
    }

    @Test("resolved keeps only current members, or nil if that breaks the sum")
    func testResolved() {
        // Cara left; Ana + Ben still sum to 100 → keep.
        #expect(split(("a", 50), ("b", 50)).resolved(for: [ana, ben, cara]) == split(("a", 50), ("b", 50)))

        // Ben left; Ana + Cara were 50/50 but only Ana remains → nil (fall back to equal).
        #expect(split(("a", 50), ("c", 50)).resolved(for: [ana, ben]) == nil)

        // Everyone still present → unchanged.
        #expect(split(("a", 60), ("b", 40)).resolved(for: [ana, ben]) == split(("a", 60), ("b", 40)))
    }

    @Test("Codable round-trips")
    func testCodable() throws {
        let s = split(("a", 70), ("b", 30))
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(DefaultSplit.self, from: data) == s)
    }
}
