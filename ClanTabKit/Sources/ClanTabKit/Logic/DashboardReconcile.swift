import Foundation

/// When the dashboard should run a fallback balance reconcile (`CHECKLIST.md`
/// "Dashboard fallback sync for missed/denied push", `DESIGN.md` §7) — the
/// time-boxed catch-up for balances a missed or denied push never carried.
/// Deliberately **not** every launch: only on the first run, or when the last
/// reconcile is older than `staleAfter`. Pull-to-refresh bypasses this and
/// reconciles unconditionally.
public enum DashboardReconcile {
    /// A cold start more than this long since the last reconcile triggers one.
    public static let staleAfter: TimeInterval = 6 * 60 * 60

    /// Pure so the cadence rule is testable without a clock or a store.
    public static func shouldReconcile(lastAt: Date?, now: Date = Date()) -> Bool {
        guard let lastAt else { return true }
        return now.timeIntervalSince(lastAt) >= staleAfter
    }
}
