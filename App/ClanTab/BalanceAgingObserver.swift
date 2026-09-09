import Foundation
import ClanTabKit

/// Feeds fresh balances into `BalanceAging` on every successful group-state
/// fetch and turns its output into scheduled / cancelled local notifications
/// (`FEATURE_BACKLOG.md` "Balance-aging nudge"). A thin value type: the pure
/// reconcile lives in `ClanTabKit`, the notification side in
/// `BalanceAgingScheduler`; both are injected so `GroupViewModelTests` can use
/// a no-op.
struct BalanceAgingObserver: Sendable {
    var store: BalanceAgingStoring
    var scheduleNudge: @Sendable (BalanceAging.ScheduledNudge, _ groupName: String) -> Void
    var cancelNudge: @Sendable (_ key: String) -> Void

    /// The signed-in member's current per-currency balances in `groupId`
    /// (nonzero entries only). Cheap to call on every poll — a no-op unless a
    /// debt just appeared or cleared.
    func observe(groupId: String, groupName: String, balances: [Balance]) {
        let map = store.load()
        let result = BalanceAging.reconcile(current: map, groupId: groupId, balances: balances)
        guard result.updated != map || !result.schedule.isEmpty || !result.cancel.isEmpty else { return }
        store.save(result.updated)
        result.cancel.forEach(cancelNudge)
        result.schedule.forEach { scheduleNudge($0, groupName) }
    }

    /// Wired to the real store + `BalanceAgingScheduler`.
    static let live = BalanceAgingObserver(
        store: UserDefaultsBalanceAgingStore(),
        scheduleNudge: { BalanceAgingScheduler.schedule($0, groupName: $1) },
        cancelNudge: { BalanceAgingScheduler.cancel(key: $0) }
    )

    /// Records aging state but schedules nothing — for tests and previews.
    static func inert(store: BalanceAgingStoring = InMemoryBalanceAgingStore()) -> BalanceAgingObserver {
        BalanceAgingObserver(store: store, scheduleNudge: { _, _ in }, cancelNudge: { _ in })
    }
}
