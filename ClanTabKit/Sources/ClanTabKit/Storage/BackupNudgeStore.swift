import Foundation

/// Persists the last time the "back up your data" nudge was shown on Group
/// Home (`FEATURE_BACKLOG.md` "Backup, in two tiers" — Tier 1: an occasional
/// reminder to use the CSV/JSON export's existing `ShareLink` path, which
/// already offers "Save to Files" / iCloud Drive / Google Drive, with zero
/// new export code). Unlike `SyncNudgeStoring`'s one-time card, this nudge is
/// meant to recur — there's no permanent dismiss, just "not now".
public protocol BackupNudgeStoring: Sendable {
    /// When the nudge was last shown, or `nil` if it never has been.
    func lastShownAt() -> Date?
    func recordShown(_ date: Date)
}

public extension BackupNudgeStoring {
    func recordShown(_ date: Date = Date()) {
        recordShown(date)
    }
}

/// Whether enough time has passed to show the backup nudge again — pure so
/// it's testable without a clock, `UserDefaults`, or a view.
public enum BackupNudge {
    /// How long the nudge stays quiet after being shown (or dismissed —
    /// there's no separate "snooze", showing it at all resets the clock).
    public static let interval: TimeInterval = 30 * 24 * 60 * 60
    /// Give a fresh install a week before the first nudge — there's nothing
    /// worth backing up yet, and it'd be the first thing a new user sees.
    public static let minimumAccountAge: TimeInterval = 7 * 24 * 60 * 60

    public static func shouldShow(now: Date = Date(), lastShownAt: Date?, firstLaunchAt: Date?) -> Bool {
        guard let firstLaunchAt, now.timeIntervalSince(firstLaunchAt) >= minimumAccountAge else { return false }
        guard let lastShownAt else { return true }
        return now.timeIntervalSince(lastShownAt) >= interval
    }
}

/// `UserDefaults`-backed nudge state.
public final class UserDefaultsBackupNudgeStore: BackupNudgeStoring, @unchecked Sendable {
    private static let lastShownKey = "clantab.backupNudge.lastShownAt"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastShownAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        let seconds = defaults.double(forKey: Self.lastShownKey)
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    public func recordShown(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(date.timeIntervalSince1970, forKey: Self.lastShownKey)
    }
}

/// In-memory nudge state for tests and previews.
public final class InMemoryBackupNudgeStore: BackupNudgeStoring, @unchecked Sendable {
    private var lastShown: Date?
    private let lock = NSLock()

    public init(lastShownAt: Date? = nil) {
        self.lastShown = lastShownAt
    }

    public func lastShownAt() -> Date? {
        lock.lock(); defer { lock.unlock() }
        return lastShown
    }

    public func recordShown(_ date: Date) {
        lock.lock(); defer { lock.unlock() }
        lastShown = date
    }
}
