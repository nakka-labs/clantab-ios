import Foundation

/// Cross-group totals for the dashboard header (`CHECKLIST.md` "Currency-
/// bucketed totals header on the dashboard"): the signed-in member's net
/// position summed across every known group, one figure per currency. The
/// currencies are never blended — no FX, a hard non-goal (`AGENTS.md`).
public enum DashboardTotals {
    /// One currency's net across all groups. `netMinor` < 0 — you owe overall
    /// in this currency; > 0 — you're owed overall. Buckets that net to zero
    /// are never produced.
    public struct CurrencyTotal: Equatable, Sendable {
        public let currency: String
        public let netMinor: Int64

        public init(currency: String, netMinor: Int64) {
            self.currency = currency
            self.netMinor = netMinor
        }
    }

    /// Sum each group's cached `myBalances` by currency. Groups whose balances
    /// have never loaded (`myBalances == nil`) are skipped, so the header
    /// reflects only what's actually known — a confirmed-empty `[]` (settled
    /// up) contributes nothing either way. Zero-net buckets are dropped.
    /// Order: first appearance across `groups` (the store returns them
    /// most-recently-opened first), matching `Balances`' currency ordering.
    public static func compute(_ groups: [KnownGroup]) -> [CurrencyTotal] {
        var totals: [String: Int64] = [:]
        var order: [String] = []
        for group in groups {
            guard let balances = group.myBalances else { continue }
            for balance in balances {
                if totals[balance.currency] == nil { order.append(balance.currency) }
                totals[balance.currency, default: 0] += balance.netMinor
            }
        }
        return order.compactMap { currency in
            let net = totals[currency] ?? 0
            return net == 0 ? nil : CurrencyTotal(currency: currency, netMinor: net)
        }
    }
}
