import Foundation

/// Whether the first-run walkthrough has been shown (`CHECKLIST.md`
/// "Onboarding walkthrough"). A single sticky flag — once the walkthrough is
/// finished or skipped it never shows again, on this device.
public protocol OnboardingStoring: Sendable {
    func hasCompletedOnboarding() -> Bool
    func markOnboardingComplete()
}

/// `UserDefaults`-backed onboarding flag.
public final class UserDefaultsOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private static let key = "clantab.onboardingComplete"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func hasCompletedOnboarding() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return defaults.bool(forKey: Self.key)
    }

    public func markOnboardingComplete() {
        lock.lock(); defer { lock.unlock() }
        defaults.set(true, forKey: Self.key)
    }
}

/// In-memory onboarding flag for tests and previews.
public final class InMemoryOnboardingStore: OnboardingStoring, @unchecked Sendable {
    private var completed: Bool
    private let lock = NSLock()

    public init(completed: Bool = false) {
        self.completed = completed
    }

    public func hasCompletedOnboarding() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return completed
    }

    public func markOnboardingComplete() {
        lock.lock(); defer { lock.unlock() }
        completed = true
    }
}
