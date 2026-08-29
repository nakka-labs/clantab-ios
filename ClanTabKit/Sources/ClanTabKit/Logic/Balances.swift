import Foundation

/// Pure derivation of member balances from the full event history of a group.
///
/// No I/O, no caching: balances are a *view* over expenses and settlements, always
/// recomputed on read — see `AGENTS.md`'s "Derived Balances" rule.
public enum Balances {
    /// Computes each member's net balance in integer minor units.
    ///
    /// For every expense, the payer is credited the full `amountMinor` (they fronted
    /// it) and every split member — which may include the payer — is debited their
    /// `amountMinor` share. For every settlement, `fromId` (who paid) is credited and
    /// `toId` (who received) is debited, since the payment reduces what `fromId` owed
    /// and what `toId` was owed.
    ///
    /// Returns exactly one `Balance` per entry in `members`, in the same order, so the
    /// result is deterministic given deterministic input and always sums to zero.
    public static func compute(
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) -> [Balance] {
        var net: [String: Int64] = [:]
        net.reserveCapacity(members.count)
        for member in members {
            net[member.id] = 0
        }

        for expense in expenses {
            net[expense.payerId, default: 0] += expense.amountMinor
            for split in expense.splits {
                net[split.memberId, default: 0] -= split.amountMinor
            }
        }

        for settlement in settlements {
            net[settlement.fromId, default: 0] += settlement.amountMinor
            net[settlement.toId, default: 0] -= settlement.amountMinor
        }

        return members.map { Balance(memberId: $0.id, netMinor: net[$0.id] ?? 0) }
    }
}
