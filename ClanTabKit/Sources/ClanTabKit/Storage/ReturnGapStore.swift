import Foundation

/// When the app was last opened (`CHECKLIST.md` "Returning-user balance
/// summary") — unlike `SyncNudgeStoring.firstLaunchAt()`, this is a *rolling*
/// timestamp advanced on every launch, so a gap since the previous one can be
/// detected each time (`ReturnGap.shouldShowWelcomeBack`).
public protocol ReturnGapStoring: Sendable {
    /// `nil` before this has ever been recorded — a fresh install, or one
    /// that predates this feature.
    func lastOpenAt() -> Date?
    func recordOpen(_ date: Date)
}

public extension ReturnGapStoring {
    func recordOpen(_ date: Date = Date()) {
        recordOpen(date)
    }
}

/// `UserDefaults`-backed last-open time.
public final class UserDefaultsReturnGapStore: ReturnGapStoring, @unchecked Sendable {
    private static let key = "clantab.returnGap.lastOpenAt"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastOpenAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        let seconds = defaults.double(forKey: Self.key)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    public func recordOpen(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(date.timeIntervalSince1970, forKey: Self.key)
    }
}

/// In-memory last-open time for tests and previews.
public final class InMemoryReturnGapStore: ReturnGapStoring, @unchecked Sendable {
    private var last: Date?
    private let lock = NSLock()

    public init(lastOpenAt: Date? = nil) {
        self.last = lastOpenAt
    }

    public func lastOpenAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return last
    }

    public func recordOpen(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        last = date
    }
}
