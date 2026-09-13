import Foundation

/// Cooldown + display logic for the "Remind" button
/// (`RemindHistoryStoring`, `CHECKLIST.md` D10) — pure, no store, no clock of
/// its own, so it's testable and identical on Linux CI.
public enum RemindHistory {
    /// How long after a reminder before the button re-enables. Not a hard
    /// server-side block (`CHECKLIST.md` "'Remind' button on an outstanding
    /// balance" already documents "no server-side rate limit for v1"), just
    /// a sane client-side default so reopening the screen can't be used to
    /// re-remind someone immediately.
    public static let cooldown: TimeInterval = 4 * 60 * 60

    /// Whether the button should stay disabled because a reminder already
    /// went out too recently. `false` for `nil` (never reminded).
    public static func isInCooldown(lastRemindedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastRemindedAt else { return false }
        return now.timeIntervalSince(lastRemindedAt) < cooldown
    }

    /// A coarse "5m ago" / "2h ago" / "3d ago" label. Hand-rolled rather than
    /// `RelativeDateTimeFormatter` — this package also runs on Linux CI
    /// (`AGENTS.md` "CI"), and this app avoids leaning on Apple-Foundation
    /// behavior nothing here exercises there (same reasoning as
    /// `CloudBackup`'s hand-rolled FNV-1a checksum). A negative gap (clock
    /// skew) floors at "Just now" rather than showing a negative duration.
    public static func relativeLabel(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = Int(seconds / 3600)
        if hours < 24 { return "\(hours)h ago" }
        let days = Int(seconds / 86_400)
        return "\(days)d ago"
    }
}
