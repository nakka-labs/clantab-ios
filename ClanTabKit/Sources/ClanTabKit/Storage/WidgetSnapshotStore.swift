import Foundation

/// A point-in-time copy of the signed-in member's own balances in the group
/// they most recently opened — the data behind the home-screen widget
/// (`FEATURE_BACKLOG.md` "Home-screen widget"). The widget extension runs in
/// a separate process with no access to the app's live `GroupViewModel`, so
/// the app writes this snapshot (to a shared App Group container) every time
/// it refetches that group's state, and the widget just reads the last one —
/// the "lightweight refresh path" the backlog calls for, rather than the
/// widget making its own network calls.
///
/// This is a *display cache*, not a second source of truth: `AGENTS.md`'s
/// "balances are always derived, never persisted" rule is about the
/// server-side data model staying consistent, not about a client caching a
/// value to render while offline or between refreshes — this snapshot is
/// always the direct, unmodified output of the same `Balances.compute` every
/// other view uses, replaced wholesale on every refresh, never patched.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public let groupId: String
    public let groupName: String
    /// This member's own balances, nonzero-only, one per active currency
    /// (`GroupViewModel.myBalances`) — empty means "all settled up," not
    /// "unknown."
    public let balances: [Balance]
    public let updatedAt: Date

    public init(groupId: String, groupName: String, balances: [Balance], updatedAt: Date) {
        self.groupId = groupId
        self.groupName = groupName
        self.balances = balances
        self.updatedAt = updatedAt
    }
}

public protocol WidgetSnapshotStoring: Sendable {
    func snapshot() -> WidgetSnapshot?
    func save(_ snapshot: WidgetSnapshot)
    /// Sign-out, or the group being left — nothing left to show, so the
    /// widget falls back to its empty state rather than a stale group.
    func clear()
}

/// `UserDefaults`-backed, meant to be constructed against an App Group suite
/// (`UserDefaults(suiteName: "group.com.clantab.app")`) shared between the
/// App and `ClanTabWidget` — the only mechanism a widget extension has for
/// reading anything the app wrote (`FEATURE_BACKLOG.md`).
public final class UserDefaultsWidgetSnapshotStore: WidgetSnapshotStoring, @unchecked Sendable {
    private static let key = "clantab.widget.snapshot"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func snapshot() -> WidgetSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: Self.key)
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }
}

/// In-memory snapshot store for tests and previews.
public final class InMemoryWidgetSnapshotStore: WidgetSnapshotStoring, @unchecked Sendable {
    private var stored: WidgetSnapshot?
    private let lock = NSLock()

    public init(_ snapshot: WidgetSnapshot? = nil) {
        self.stored = snapshot
    }

    public func snapshot() -> WidgetSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ snapshot: WidgetSnapshot) {
        lock.lock(); defer { lock.unlock() }
        stored = snapshot
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
