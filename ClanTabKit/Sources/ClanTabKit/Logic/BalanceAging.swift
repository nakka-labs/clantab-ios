import Foundation

/// One tracked debt: when the signed-in member's balance in a
/// (group, currency) first went into the red, and whether the "you've owed X
/// for a while" nudge has already fired for this episode.
public struct BalanceAgingEntry: Codable, Sendable, Equatable {
    public var owedSince: Date
    public var nudged: Bool

    public init(owedSince: Date, nudged: Bool = false) {
        self.owedSince = owedSince
        self.nudged = nudged
    }
}

/// The balance-aging nudge (`FEATURE_BACKLOG.md` "Balance-aging nudge"): a
/// local notification when the signed-in member has *owed* money in a group
/// for a while. State-driven, **not a fixed calendar cadence** — the clock
/// starts when a debt first appears and resets the moment it clears; there's
/// one nudge per debt episode (clear it and re-incur, and it re-arms).
///
/// Pure: `reconcile` takes the current aging map + the member's current
/// balances and returns the new map plus notification actions for the app to
/// carry out. No `UNUserNotificationCenter`, no clock, no store.
public enum BalanceAging {
    /// How long a debt must persist before the nudge fires.
    public static let threshold: TimeInterval = 14 * 24 * 60 * 60
    /// Debts smaller than this (₹1 / $1 …) aren't worth a notification.
    public static let minimumMinor: Int64 = 100

    /// A nudge the app should schedule as a one-shot local notification.
    public struct ScheduledNudge: Equatable, Sendable {
        /// `"<groupId>\t<currency>"` — the notification-request identifier too.
        public let key: String
        public let groupId: String
        public let currency: String
        /// Magnitude owed, in minor units (always positive).
        public let owedMinor: Int64
        public let owedSince: Date
        /// When the notification should fire — never in the past.
        public let fireDate: Date
    }

    /// Whole days a debt has been outstanding.
    public static func daysOwed(since: Date, now: Date = Date()) -> Int {
        max(0, Int(now.timeIntervalSince(since) / 86_400))
    }

    static func key(groupId: String, currency: String) -> String { "\(groupId)\t\(currency)" }

    /// Fold the member's current balances in one group into the aging map.
    ///
    /// - A currency newly in the red past `minimumMinor` starts its clock and
    ///   is scheduled for a nudge at `owedSince + threshold`.
    /// - A currency that cleared (settled, back in credit, or now below the
    ///   minimum) drops out and its pending nudge is cancelled.
    /// - A still-red currency keeps its clock; once `owedSince + threshold`
    ///   has passed it's marked `nudged` (the OS notification has fired), and
    ///   an un-fired one is re-emitted so `add(_:)` can refresh it idempotently
    ///   (covers a reinstall / a toggled notification permission).
    ///
    /// `balances` is the signed-in member's own per-currency balance in this
    /// group (nonzero entries only, as `Balances.compute` returns).
    public static func reconcile(
        current: [String: BalanceAgingEntry],
        groupId: String,
        balances: [Balance],
        now: Date = Date()
    ) -> (updated: [String: BalanceAgingEntry], schedule: [ScheduledNudge], cancel: [String]) {
        var updated = current
        var schedule: [ScheduledNudge] = []
        var cancel: [String] = []

        let debts: [String: Int64] = Dictionary(
            uniqueKeysWithValues: balances
                .filter { $0.netMinor <= -minimumMinor }
                .map { ($0.currency, -$0.netMinor) }
        )
        let prefix = groupId + "\t"

        for existingKey in current.keys where existingKey.hasPrefix(prefix) {
            let currency = String(existingKey.dropFirst(prefix.count))
            if debts[currency] == nil {
                updated[existingKey] = nil
                cancel.append(existingKey)
            }
        }

        for (currency, owedMinor) in debts {
            let k = key(groupId: groupId, currency: currency)
            let fireAt = { (since: Date) in max(since.addingTimeInterval(threshold), now.addingTimeInterval(60)) }

            if var entry = current[k] {
                guard !entry.nudged else { continue }
                if now.timeIntervalSince(entry.owedSince) >= threshold {
                    entry.nudged = true
                    updated[k] = entry
                } else {
                    schedule.append(ScheduledNudge(
                        key: k, groupId: groupId, currency: currency,
                        owedMinor: owedMinor, owedSince: entry.owedSince,
                        fireDate: fireAt(entry.owedSince)
                    ))
                }
            } else {
                let entry = BalanceAgingEntry(owedSince: now)
                updated[k] = entry
                schedule.append(ScheduledNudge(
                    key: k, groupId: groupId, currency: currency,
                    owedMinor: owedMinor, owedSince: now,
                    fireDate: fireAt(now)
                ))
            }
        }

        return (updated, schedule, cancel)
    }
}
