import Foundation

/// Pure derivation of member balances from the full event history of a group.
///
/// No I/O, no caching: balances are a *view* over expenses and settlements, always
/// recomputed on read — see `AGENTS.md`'s "Derived Balances" rule.
public enum Balances {
    /// Computes each member's net balance, **partitioned by currency** — a group
    /// is not restricted to one currency and the ledgers are never blended (no
    /// FX). Within each currency bucket:
    ///
    /// - the payer of an expense is credited the full `amountMinor` (they fronted
    ///   it) and every split member — which may include the payer — is debited
    ///   their share;
    /// - for a settlement, `fromId` (who paid) is credited and `toId` (who
    ///   received) is debited.
    ///
    /// Returns one `Balance` per (member, currency) pair **that nets to a nonzero
    /// amount**, ordered by currency (in first-appearance order across the
    /// combined expense-then-settlement stream) and then by `members` order.
    /// Every currency bucket sums to zero. A group with no activity yields `[]`.
    public static func compute(
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) -> [Balance] {
        // currency -> (memberId -> net), plus the order currencies first appear.
        var byCurrency: [String: [String: Int64]] = [:]
        var currencyOrder: [String] = []

        func bucket(_ currency: String) -> Void {
            if byCurrency[currency] == nil {
                byCurrency[currency] = [:]
                currencyOrder.append(currency)
            }
        }

        for expense in expenses {
            bucket(expense.currency)
            byCurrency[expense.currency]![expense.payerId, default: 0] += expense.amountMinor
            for split in expense.splits {
                byCurrency[expense.currency]![split.memberId, default: 0] -= split.amountMinor
            }
        }

        for settlement in settlements {
            bucket(settlement.currency)
            byCurrency[settlement.currency]![settlement.fromId, default: 0] += settlement.amountMinor
            byCurrency[settlement.currency]![settlement.toId, default: 0] -= settlement.amountMinor
        }

        var result: [Balance] = []
        for currency in currencyOrder {
            let nets = byCurrency[currency]!
            for member in members {
                let net = nets[member.id] ?? 0
                if net != 0 {
                    result.append(Balance(memberId: member.id, currency: currency, netMinor: net))
                }
            }
        }
        return result
    }

    /// The one balance to headline when there's only room for one — the
    /// largest-magnitude nonzero currency. Used by the home-screen widget
    /// (`FEATURE_BACKLOG.md`), which can't show every currency a
    /// multi-currency group's member is active in. `nil` means "all settled
    /// up," not "unknown."
    public static func headline(_ balances: [Balance]) -> Balance? {
        balances.filter { $0.netMinor != 0 }.max { abs($0.netMinor) < abs($1.netMinor) }
    }
}
