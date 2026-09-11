import Foundation

/// The build number ("What's New" sheet, `CHECKLIST.md`) the user last saw a
/// launch of — distinct from `OnboardingStoring`'s one-time "finished the
/// walkthrough" flag: this one keeps advancing every launch, seeding what
/// counts as "new" the next time a build ships something worth mentioning.
public protocol WhatsNewStoring: Sendable {
    /// `nil` before this has ever been set — a fresh install, or one that
    /// predates this feature. Distinct from `0`: a build number of `0` would
    /// otherwise be indistinguishable from "never recorded."
    func lastSeenBuild() -> Int?
    func markSeen(build: Int)
}

/// `UserDefaults`-backed "What's New" last-seen-build.
public final class UserDefaultsWhatsNewStore: WhatsNewStoring, @unchecked Sendable {
    private static let key = "clantab.whatsNewLastSeenBuild"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func lastSeenBuild() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return defaults.object(forKey: Self.key) as? Int
    }

    public func markSeen(build: Int) {
        lock.lock(); defer { lock.unlock() }
        defaults.set(build, forKey: Self.key)
    }
}

/// In-memory "What's New" store for tests and previews.
public final class InMemoryWhatsNewStore: WhatsNewStoring, @unchecked Sendable {
    private var seen: Int?
    private let lock = NSLock()

    public init(lastSeenBuild: Int? = nil) {
        self.seen = lastSeenBuild
    }

    public func lastSeenBuild() -> Int? {
        lock.lock(); defer { lock.unlock() }
        return seen
    }

    public func markSeen(build: Int) {
        lock.lock(); defer { lock.unlock() }
        seen = build
    }
}
