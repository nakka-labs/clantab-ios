import Foundation

/// Whether enough time has passed since the last open to show a "Welcome
/// back" balance summary (`CHECKLIST.md` "Returning-user balance summary") —
/// pure, so it's testable without a clock, `UserDefaults`, or a view.
public enum ReturnGap {
    /// How long since the last open counts as "a gap" worth welcoming the
    /// user back for, rather than just picking up where they left off.
    public static let threshold: TimeInterval = 3 * 24 * 60 * 60

    /// `nil` `lastOpenAt` — a fresh install, or a user who predates this
    /// feature — never shows the card; there's nothing to "welcome back"
    /// from yet. The caller records an open every launch regardless
    /// (`ReturnGapStoring.recordOpen`), which both seeds this for next time
    /// and resets the gap the moment the card is shown once.
    public static func shouldShowWelcomeBack(now: Date = Date(), lastOpenAt: Date?) -> Bool {
        guard let lastOpenAt else { return false }
        return now.timeIntervalSince(lastOpenAt) >= threshold
    }
}
