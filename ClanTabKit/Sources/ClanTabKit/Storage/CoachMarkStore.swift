import Foundation

/// Whether a one-time contextual tip ("coach mark", `CHECKLIST.md` "One-time
/// contextual coach marks") has been shown and dismissed — one flag per tip
/// `id`, same `UserDefaults`-flag idea as `OnboardingStoring`, just keyed
/// instead of singular so many independent tips share one store.
public protocol CoachMarkStoring: Sendable {
    func hasSeen(_ id: String) -> Bool
    func markSeen(_ id: String)
    /// Clears every recorded tip so they all show again — Settings "Show
    /// tips again" (`CHECKLIST.md`).
    func resetAll()
}

/// `UserDefaults`-backed coach-mark flags — every seen id kept in one array
/// under a single key, rather than one key per id (there's no fixed,
/// enumerable id list otherwise for `resetAll` to walk).
public final class UserDefaultsCoachMarkStore: CoachMarkStoring, @unchecked Sendable {
    private static let key = "clantab.coachMarks.seen"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasSeen(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return (defaults.array(forKey: Self.key) as? [String] ?? []).contains(id)
    }

    public func markSeen(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        var seen = Set(defaults.array(forKey: Self.key) as? [String] ?? [])
        seen.insert(id)
        defaults.set(Array(seen), forKey: Self.key)
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: Self.key)
    }
}

/// In-memory coach-mark flags for tests and previews.
public final class InMemoryCoachMarkStore: CoachMarkStoring, @unchecked Sendable {
    private var seen: Set<String>
    private let lock = NSLock()

    public init(seen: Set<String> = []) {
        self.seen = seen
    }

    public func hasSeen(_ id: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return seen.contains(id)
    }

    public func markSeen(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        seen.insert(id)
    }

    public func resetAll() {
        lock.lock(); defer { lock.unlock() }
        seen.removeAll()
    }
}
