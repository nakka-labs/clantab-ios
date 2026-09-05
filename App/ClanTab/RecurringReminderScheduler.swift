import Foundation
import UserNotifications
import ClanTabKit

/// Schedules/cancels the local notification behind a `RecurringTemplate`
/// (`FEATURE_BACKLOG.md` "Recurring reminders"). Deliberately `UNUserNotificationCenter`-only
/// — no server push infra, no auto-post; the notification just opens the app,
/// same as tapping any other notification. Kept out of `ClanTabKit`:
/// `UserNotifications` is an Apple-only framework (`NAV_POLISH_PLAN.md` Part 3
/// guardrail — the pure template model + schedule math stay platform-neutral).
enum RecurringReminderScheduler {
    /// Prompts the system permission sheet if not yet decided. Returns
    /// whether reminders can actually be scheduled — the caller should tell
    /// the user why nothing happens if this is `false` (they said no, or a
    /// parental-controls / MDM restriction is in effect).
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default:
            return false
        }
    }

    /// A repeating calendar-triggered notification — the OS handles the
    /// recurrence, no app code needs to run in the background to reschedule
    /// it. Overwrites any existing request with the same `template.id`.
    static func schedule(_ template: RecurringTemplate) {
        let content = UNMutableNotificationContent()
        content.title = "Log this expense?"
        content.body = "\(template.description) — \(MoneyFormat.string(minorUnits: template.amountMinor, currency: template.currency))"
        content.sound = .default
        content.userInfo = ["groupId": template.groupId, "templateId": template.id]

        let trigger = UNCalendarNotificationTrigger(dateMatching: RecurringSchedule.dateComponents(for: template), repeats: true)
        let request = UNNotificationRequest(identifier: template.id, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancel(templateId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [templateId])
    }
}
