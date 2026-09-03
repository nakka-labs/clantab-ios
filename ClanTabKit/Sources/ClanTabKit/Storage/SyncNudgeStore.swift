import Foundation

/// Persists the tiny bit of state behind the one-time "sign in to keep your
/// groups" nudge (`ACCOUNTS_DESIGN.md` §10): when the app was first used, and
/// whether the user has dismissed the card. Once dismissed it never shows again.
public protocol SyncNudgeStoring: Sendable {
    /// When the app was first launched, or `nil` if never recorded.
    func firstLaunchAt() -> Date?
    /// Record the first-launch time. A no-op once it's already set, so it's safe
    /// to call on every launch.
    func recordFirstLaunch(_ date: Date)
    func isDismissed() -> Bool
    func dismiss()
}

public extension SyncNudgeStoring {
    func recordFirstLaunch(_ date: Date = Date()) {
        recordFirstLaunch(date)
    }
}

/// `UserDefaults`-backed nudge state.
public final class UserDefaultsSyncNudgeStore: SyncNudgeStoring, @unchecked Sendable {
    private static let firstLaunchKey = "clantab.nudge.firstLaunchAt"
    private static let dismissedKey = "clantab.nudge.dismissed"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func firstLaunchAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        let seconds = defaults.double(forKey: Self.firstLaunchKey)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    public func recordFirstLaunch(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        guard defaults.double(forKey: Self.firstLaunchKey) == 0 else { return }
        defaults.set(date.timeIntervalSince1970, forKey: Self.firstLaunchKey)
    }

    public func isDismissed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return defaults.bool(forKey: Self.dismissedKey)
    }

    public func dismiss() {
        lock.lock(); defer { lock.unlock() }
        defaults.set(true, forKey: Self.dismissedKey)
    }
}

/// In-memory nudge state for tests and previews.
public final class InMemorySyncNudgeStore: SyncNudgeStoring, @unchecked Sendable {
    private var firstLaunch: Date?
    private var dismissed: Bool
    private let lock = NSLock()

    public init(firstLaunchAt: Date? = nil, dismissed: Bool = false) {
        self.firstLaunch = firstLaunchAt
        self.dismissed = dismissed
    }

    public func firstLaunchAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return firstLaunch
    }

    public func recordFirstLaunch(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        if firstLaunch == nil { firstLaunch = date }
    }

    public func isDismissed() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return dismissed
    }

    public func dismiss() {
        lock.lock(); defer { lock.unlock() }
        dismissed = true
    }
}
