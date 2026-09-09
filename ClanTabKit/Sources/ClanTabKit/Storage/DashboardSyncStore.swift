import Foundation

/// Persists the one timestamp behind the dashboard's fallback balance
/// reconcile (`CHECKLIST.md` "Dashboard fallback sync for missed/denied
/// push"): when the last successful reconcile ran, so the next cold start
/// can decide whether it's due (`DashboardReconcile.shouldReconcile`).
public protocol DashboardSyncStoring: Sendable {
    func lastReconcileAt() -> Date?
    func recordReconcile(_ date: Date)
}

public extension DashboardSyncStoring {
    func recordReconcile(_ date: Date = Date()) { recordReconcile(date) }
}

/// `UserDefaults`-backed reconcile timestamp.
public final class UserDefaultsDashboardSyncStore: DashboardSyncStoring, @unchecked Sendable {
    private static let key = "clantab.dashboard.lastReconcileAt"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastReconcileAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        let seconds = defaults.double(forKey: Self.key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    public func recordReconcile(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(date.timeIntervalSince1970, forKey: Self.key)
    }
}

/// In-memory reconcile timestamp for tests and previews.
public final class InMemoryDashboardSyncStore: DashboardSyncStoring, @unchecked Sendable {
    private var last: Date?
    private let lock = NSLock()

    public init(lastReconcileAt: Date? = nil) {
        self.last = lastReconcileAt
    }

    public func lastReconcileAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return last
    }

    public func recordReconcile(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        last = date
    }
}
