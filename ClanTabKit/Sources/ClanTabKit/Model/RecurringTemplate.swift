import Foundation

/// A recurring expense reminder — schedules a local notification ("Log this
/// month's rent?"); the user still confirms/adjusts and taps Add, same as
/// Duplicate (`FEATURE_BACKLOG.md` "Recurring reminders (not auto-post)").
/// Auto-post (silently creating the expense) is deliberately out of scope —
/// a shared, no-hidden-owner ledger where expenses appear with nobody having
/// actively added them is exactly the trust problem trash/attribution exists
/// to fix.
///
/// Scoped down from the backlog's "amount, payer, split, cadence": the split
/// itself isn't stored — every reminder splits equally among whoever's
/// *currently* a member when it's turned into an expense, sidestepping the
/// stale-member problem for splits entirely (not just for the payer, which
/// `RecurringTemplateValidation` below still checks explicitly since it *is*
/// stored).
public struct RecurringTemplate: Codable, Sendable, Equatable, Identifiable {
    public enum Cadence: String, Codable, Sendable, CaseIterable {
        case weekly
        case monthly

        public var label: String {
            switch self {
            case .weekly: return "Weekly"
            case .monthly: return "Monthly"
            }
        }
    }

    public let id: String
    public let groupId: String
    public var description: String
    public var amountMinor: Int64
    public var currency: String
    /// The memberId to pre-fill as payer — checked for continued membership
    /// by `RecurringTemplateValidation.validity` each time the reminder is
    /// shown or fires; a removed member needs "this reminder needs updating"
    /// rather than silently pre-filling with someone no longer in the group.
    public var payerId: String
    public var category: String?
    public var categoryIcon: String?
    public var cadence: Cadence
    /// For `.weekly`: `Calendar.Component.weekday` (1 = Sunday ... 7 = Saturday).
    /// For `.monthly`: day of month (1...31; a month shorter than this clamps
    /// to its last day, standard `DateComponents` matching behavior).
    public var cadenceAnchor: Int
    public var createdAt: Date

    public init(
        id: String,
        groupId: String,
        description: String,
        amountMinor: Int64,
        currency: String,
        payerId: String,
        category: String? = nil,
        categoryIcon: String? = nil,
        cadence: Cadence,
        cadenceAnchor: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.description = description
        self.amountMinor = amountMinor
        self.currency = currency
        self.payerId = payerId
        self.category = category
        self.categoryIcon = categoryIcon
        self.cadence = cadence
        self.cadenceAnchor = cadenceAnchor
        self.createdAt = createdAt
    }
}

/// Whether a template's stored `payerId` is still safe to pre-fill with.
public enum RecurringTemplateValidity: Equatable, Sendable {
    case valid
    /// The payer isn't a current member — the app should surface "this
    /// reminder needs updating" rather than silently pre-filling with them.
    case payerNoLongerAMember
}

public enum RecurringTemplateValidation {
    public static func validity(of template: RecurringTemplate, members: [Member]) -> RecurringTemplateValidity {
        members.contains { $0.id == template.payerId } ? .valid : .payerNoLongerAMember
    }
}

/// Pure next-fire-date computation — no `UNUserNotificationCenter` dependency,
/// so it's testable without a real notification center. The app uses the
/// same `DateComponents` shape to build the actual `UNCalendarNotificationTrigger`.
public enum RecurringSchedule {
    /// 9 AM local time on the matching weekday/day-of-month, strictly after
    /// `date`.
    public static func nextFireDate(
        for template: RecurringTemplate,
        after date: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        var components = dateComponents(for: template)
        components.hour = 9
        components.minute = 0
        return calendar.nextDate(after: date, matching: components, matchingPolicy: .nextTimePreservingSmallerComponents)
    }

    /// The `DateComponents` a `UNCalendarNotificationTrigger(dateMatching:repeats:)`
    /// should match against — `hour`/`minute` included so the trigger fires
    /// at a predictable time, not "as soon as possible" on the matching day.
    public static func dateComponents(for template: RecurringTemplate) -> DateComponents {
        var components = DateComponents()
        switch template.cadence {
        case .weekly:
            components.weekday = template.cadenceAnchor
        case .monthly:
            components.day = template.cadenceAnchor
        }
        components.hour = 9
        components.minute = 0
        return components
    }
}
