import Testing
import Foundation
@testable import ClanTabKit

@Suite("DashboardTotals")
struct DashboardTotalsTests {

    private func group(_ id: String, _ balances: [Balance]?) -> KnownGroup {
        KnownGroup(groupId: id, name: id, lastOpenedAt: Date(), myBalances: balances)
    }

    private func bal(_ currency: String, _ net: Int64) -> Balance {
        Balance(memberId: "me", currency: currency, netMinor: net)
    }

    @Test("Empty input yields no totals")
    func testEmpty() {
        #expect(DashboardTotals.compute([]) == [])
    }

    @Test("Sums one currency across groups, keeping the sign")
    func testOneCurrencyAcrossGroups() {
        let totals = DashboardTotals.compute([
            group("a", [bal("INR", -500)]),
            group("b", [bal("INR", -200)]),
            group("c", [bal("INR", 300)]),
        ])
        #expect(totals == [.init(currency: "INR", netMinor: -400)])
    }

    @Test("Currencies are bucketed separately, never blended")
    func testMultiCurrencyBuckets() {
        let totals = DashboardTotals.compute([
            group("a", [bal("INR", -500)]),
            group("b", [bal("USD", 2000)]),
        ])
        #expect(totals == [
            .init(currency: "INR", netMinor: -500),
            .init(currency: "USD", netMinor: 2000),
        ])
    }

    @Test("A currency that nets to zero across groups is dropped")
    func testZeroNetBucketDropped() {
        let totals = DashboardTotals.compute([
            group("a", [bal("INR", -500), bal("USD", 100)]),
            group("b", [bal("INR", 500)]),
        ])
        #expect(totals == [.init(currency: "USD", netMinor: 100)])
    }

    @Test("Groups whose balances never loaded are skipped; settled-up groups contribute nothing")
    func testNilAndEmptyBalances() {
        let totals = DashboardTotals.compute([
            group("a", nil),
            group("b", []),
            group("c", [bal("INR", -750)]),
        ])
        #expect(totals == [.init(currency: "INR", netMinor: -750)])
    }

    @Test("All groups settled or unloaded yields no totals")
    func testNothingOwed() {
        #expect(DashboardTotals.compute([group("a", nil), group("b", [])]) == [])
    }

    @Test("Currency order follows first appearance across the groups list")
    func testCurrencyOrder() {
        let totals = DashboardTotals.compute([
            group("a", [bal("USD", 10)]),
            group("b", [bal("EUR", 20)]),
            group("c", [bal("INR", 30)]),
        ])
        #expect(totals.map(\.currency) == ["USD", "EUR", "INR"])
    }
}
