import XCTest
import ClanTabKit
@testable import ClanTab

final class BalanceAgingObserverTests: XCTestCase {

    /// `@Sendable`-safe capture box for the scheduler/canceller spies.
    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var _scheduled: [BalanceAging.ScheduledNudge] = []
        private var _cancelled: [String] = []
        func schedule(_ n: BalanceAging.ScheduledNudge) { lock.lock(); _scheduled.append(n); lock.unlock() }
        func cancel(_ k: String) { lock.lock(); _cancelled.append(k); lock.unlock() }
        var scheduled: [BalanceAging.ScheduledNudge] { lock.lock(); defer { lock.unlock() }; return _scheduled }
        var cancelled: [String] { lock.lock(); defer { lock.unlock() }; return _cancelled }
    }

    private func bal(_ currency: String, _ net: Int64) -> Balance {
        Balance(memberId: "me", currency: currency, netMinor: net)
    }

    private func observer(_ store: BalanceAgingStoring) -> (BalanceAgingObserver, Recorder) {
        let rec = Recorder()
        let obs = BalanceAgingObserver(
            store: store,
            scheduleNudge: { n, _ in rec.schedule(n) },
            cancelNudge: { k in rec.cancel(k) }
        )
        return (obs, rec)
    }

    func testObserveRecordsANewDebtAndSchedules() {
        let store = InMemoryBalanceAgingStore()
        let (obs, rec) = observer(store)

        obs.observe(groupId: "g1", groupName: "Goa", balances: [bal("INR", -50000)])

        XCTAssertEqual(store.load().keys.sorted(), ["g1\tINR"])
        XCTAssertEqual(rec.scheduled.map(\.key), ["g1\tINR"])
        XCTAssertEqual(rec.scheduled.first?.owedMinor, 50000)
    }

    func testObserveCancelsWhenTheDebtClears() {
        let store = InMemoryBalanceAgingStore(["g1\tINR": BalanceAgingEntry(owedSince: .now, nudged: true)])
        let (obs, rec) = observer(store)

        obs.observe(groupId: "g1", groupName: "Goa", balances: []) // settled

        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(rec.cancelled, ["g1\tINR"])
    }

    func testObserveIsANoOpWhenNothingChanged() {
        let store = InMemoryBalanceAgingStore(["g1\tINR": BalanceAgingEntry(owedSince: .now, nudged: true)])
        let (obs, rec) = observer(store)

        obs.observe(groupId: "g1", groupName: "Goa", balances: [bal("INR", -50000)]) // still owed, already nudged

        XCTAssertTrue(rec.scheduled.isEmpty)
        XCTAssertTrue(rec.cancelled.isEmpty)
    }
}
