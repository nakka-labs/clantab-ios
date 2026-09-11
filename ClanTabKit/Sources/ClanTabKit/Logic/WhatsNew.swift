import Foundation

/// One release's worth of "What's New" copy (`CHECKLIST.md` "'What's New'
/// sheet, versioned") — a static list a developer edits by hand each release
/// that has something worth telling a *returning* user about (not every
/// build needs an entry), same shape as `CHECKLIST.md`'s own "Done" writeups
/// condensed to user-facing language.
public struct WhatsNewRelease: Identifiable, Sendable, Equatable {
    /// The `CFBundleVersion` this release shipped as.
    public let build: Int
    public var id: Int { build }
    public let headline: String
    public let items: [String]

    public init(build: Int, headline: String, items: [String]) {
        self.build = build
        self.headline = headline
        self.items = items
    }
}

/// Pure "what should the launch sheet show" logic — no `UserDefaults`, no
/// SwiftUI, so it's testable without standing up a view. `WhatsNewStoring`
/// holds the one piece of state (`lastSeenBuild`) this reads and advances.
public enum WhatsNew {
    /// Newest first; order doesn't matter to the logic below (`build` is what's
    /// compared), just to whoever's editing this list by hand.
    public static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            build: 9,
            headline: "New this update",
            items: [
                "Friends: see everyone you split with across every group, and settle up 1:1 without a shared group.",
                "Comment on any expense.",
                "Split one expense across multiple payers.",
                "Split by shares (2:1 ratios), not just percentages.",
                "Tax and tip on an itemized expense now split by what each person ordered.",
                "Tap a member in Insights to see just their spending; a new pie chart for categories.",
                "Remind someone who owes you, right from their profile.",
            ]
        ),
    ]

    /// Every release strictly newer than `lastSeenBuild`, oldest first (the
    /// order a changelog reads in) — empty if there's nothing new or
    /// `lastSeenBuild` is `nil` (the caller's job to decide what a fresh
    /// install does; this just answers "what's newer than X").
    public static func unseenReleases(sinceBuild lastSeenBuild: Int?) -> [WhatsNewRelease] {
        guard let lastSeenBuild else { return [] }
        return releases.filter { $0.build > lastSeenBuild }.sorted { $0.build < $1.build }
    }

    /// Whether the launch sheet should appear: the first-run walkthrough is
    /// already behind the user (a fresh install gets onboarding, not a
    /// changelog for updates it never saw), `lastSeenBuild` is a real
    /// recorded value (not a fresh install / pre-feature user — those seed
    /// silently instead, see `RootView`), and there's at least one release
    /// between it and `currentBuild`.
    public static func shouldShow(lastSeenBuild: Int?, currentBuild: Int, hasCompletedOnboarding: Bool) -> Bool {
        guard hasCompletedOnboarding, let lastSeenBuild, lastSeenBuild < currentBuild else { return false }
        return !unseenReleases(sinceBuild: lastSeenBuild).isEmpty
    }
}
