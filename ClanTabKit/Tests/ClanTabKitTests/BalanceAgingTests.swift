import Testing
import Foundation
@testable import ClanTabKit

@Suite("BalanceAging")
struct BalanceAgingTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private func bal(_ currency: String, _ net: Int64) -> Balance {
        Balance(memberId: "me", currency: currency, netMinor: net)
    }

    // MARK: - daysOwed

    @Test("daysOwed counts whole elapsed days")
    func testDaysOwed() {
        #expect(BalanceAging.daysOwed(since: t0, now: t0.addingTimeInterval(0)) == 0)
        #expect(BalanceAging.daysOwed(since: t0, now: t0.addingTimeInterval(3.5 * day)) == 3)
        #expect(BalanceAging.daysOwed(since: t0, now: t0.addingTimeInterval(14 * day)) == 14)
    }

    // MARK: - reconcile

    @Test("a new debt past the minimum starts a clock and schedules a nudge")
    func testNewDebtStartsClock() {
        let r = BalanceAging.reconcile(current: [:], groupId: "g1", balances: [bal("INR", -50000)], now: t0)

        #expect(r.updated == ["g1\tINR": BalanceAgingEntry(owedSince: t0)])
        #expect(r.cancel.isEmpty)
        #expect(r.schedule.count == 1)
        let n = r.schedule[0]
        #expect(n.key == "g1\tINR")
        #expect(n.owedMinor == 50000)
        #expect(n.fireDate == t0.addingTimeInterval(BalanceAging.threshold))
    }

    @Test("a tiny debt below the minimum is ignored")
    func testTinyDebtIgnored() {
        let r = BalanceAging.reconcile(current: [:], groupId: "g1", balances: [bal("INR", -50)], now: t0)
        #expect(r.updated.isEmpty)
        #expect(r.schedule.isEmpty)
    }

    @Test("being owed money is never nudge-worthy")
    func testCreditNotTracked() {
        let r = BalanceAging.reconcile(current: [:], groupId: "g1", balances: [bal("INR", 90000)], now: t0)
        #expect(r.updated.isEmpty)
        #expect(r.schedule.isEmpty)
    }

    @Test("a persistent debt keeps its original owedSince")
    func testPersistentDebtKeepsClock() {
        let start = BalanceAgingEntry(owedSince: t0)
        let r = BalanceAging.reconcile(
            current: ["g1\tINR": start],
            groupId: "g1", balances: [bal("INR", -60000)],
            now: t0.addingTimeInterval(5 * day)
        )
        #expect(r.updated["g1\tINR"] == start) // unchanged
        #expect(r.schedule.count == 1) // re-emitted idempotently
        #expect(r.schedule[0].fireDate == t0.addingTimeInterval(BalanceAging.threshold))
    }

    @Test("once the threshold passes the entry is marked nudged and not rescheduled")
    func testThresholdPassedMarksNudged() {
        let r = BalanceAging.reconcile(
            current: ["g1\tINR": BalanceAgingEntry(owedSince: t0)],
            groupId: "g1", balances: [bal("INR", -60000)],
            now: t0.addingTimeInterval(BalanceAging.threshold + day)
        )
        #expect(r.updated["g1\tINR"] == BalanceAgingEntry(owedSince: t0, nudged: true))
        #expect(r.schedule.isEmpty)
    }

    @Test("an already-nudged debt does nothing more")
    func testNudgedDebtIsQuiet() {
        let entry = BalanceAgingEntry(owedSince: t0, nudged: true)
        let r = BalanceAging.reconcile(
            current: ["g1\tINR": entry],
            groupId: "g1", balances: [bal("INR", -60000)],
            now: t0.addingTimeInterval(20 * day)
        )
        #expect(r.updated == ["g1\tINR": entry])
        #expect(r.schedule.isEmpty)
        #expect(r.cancel.isEmpty)
    }

    @Test("a cleared debt drops out and cancels its nudge")
    func testClearedDebtCancels() {
        let r = BalanceAging.reconcile(
            current: ["g1\tINR": BalanceAgingEntry(owedSince: t0, nudged: true)],
            groupId: "g1", balances: [], // settled up
            now: t0.addingTimeInterval(10 * day)
        )
        #expect(r.updated.isEmpty)
        #expect(r.cancel == ["g1\tINR"])
    }

    @Test("re-incurring a debt after clearing it re-arms with a fresh clock")
    func testReIncurReArms() {
        let cleared = BalanceAging.reconcile(
            current: ["g1\tINR": BalanceAgingEntry(owedSince: t0, nudged: true)],
            groupId: "g1", balances: [], now: t0.addingTimeInterval(10 * day)
        ).updated
        let reIncurred = BalanceAging.reconcile(
            current: cleared, groupId: "g1", balances: [bal("INR", -40000)],
            now: t0.addingTimeInterval(20 * day)
        )
        #expect(reIncurred.updated["g1\tINR"] == BalanceAgingEntry(owedSince: t0.addingTimeInterval(20 * day)))
        #expect(reIncurred.schedule.count == 1)
    }

    @Test("currencies and groups are tracked independently")
    func testMultiCurrencyAndGroup() {
        var map: [String: BalanceAgingEntry] = [:]
        map = BalanceAging.reconcile(current: map, groupId: "g1", balances: [bal("INR", -50000), bal("USD", -8000)], now: t0).updated
        #expect(Set(map.keys) == ["g1\tINR", "g1\tUSD"])

        // g1's USD clears, INR stays; g2 gains a debt. g1's INR must survive.
        let r = BalanceAging.reconcile(current: map, groupId: "g1", balances: [bal("INR", -50000)], now: t0.addingTimeInterval(day))
        #expect(Set(r.updated.keys) == ["g1\tINR"])
        #expect(r.cancel == ["g1\tUSD"])

        let r2 = BalanceAging.reconcile(current: r.updated, groupId: "g2", balances: [bal("INR", -30000)], now: t0.addingTimeInterval(day))
        #expect(Set(r2.updated.keys) == ["g1\tINR", "g2\tINR"])
    }
}
