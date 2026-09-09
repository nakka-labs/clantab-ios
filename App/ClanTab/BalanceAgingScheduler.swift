import Foundation
import UserNotifications
import ClanTabKit

/// Schedules / cancels the one-shot local notification behind the
/// balance-aging nudge (`FEATURE_BACKLOG.md` "Balance-aging nudge"). Same
/// `UNUserNotificationCenter`-only, no-server-push shape as
/// `RecurringReminderScheduler` — the notification just opens the group
/// (`userInfo["groupId"]`, routed through `AppDelegate` like any push tap).
///
/// **Never prompts for permission.** The aging nudge is automatic, so it only
/// schedules when notifications are *already* authorized (e.g. the user turned
/// on a recurring reminder); otherwise it silently does nothing.
enum BalanceAgingScheduler {
    static func schedule(_ nudge: BalanceAging.ScheduledNudge, groupName: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                break
            default:
                return // no prompt — see the type doc
            }

            let content = UNMutableNotificationContent()
            content.title = "Time to settle up?"
            let amount = MoneyFormat.string(minorUnits: nudge.owedMinor, currency: nudge.currency)
            let days = BalanceAging.daysOwed(since: nudge.owedSince, now: nudge.fireDate)
            content.body = "You've owed \(amount) in \(groupName) for \(days) days."
            content.sound = .default
            content.userInfo = ["groupId": nudge.groupId]

            let trigger = Self.trigger(for: nudge.fireDate)
            center.add(UNNotificationRequest(identifier: nudge.key, content: content, trigger: trigger))
        }
    }

    static func cancel(key: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [key])
    }

    /// A date-specific calendar trigger for a future fire date; a short
    /// time-interval trigger when it's essentially now (a past-due debt found
    /// on launch — a calendar trigger for an instant already gone never fires).
    private static func trigger(for fireDate: Date) -> UNNotificationTrigger {
        let interval = fireDate.timeIntervalSinceNow
        if interval <= 90 {
            return UNTimeIntervalNotificationTrigger(timeInterval: max(1, min(interval, 90)), repeats: false)
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        return UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    }
}
