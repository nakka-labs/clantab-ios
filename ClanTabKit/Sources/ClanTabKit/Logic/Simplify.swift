import Foundation

/// Greedy debt-simplification: collapses a group's tangled pairwise IOUs down to the
/// minimum possible number of settle-up transactions (at most N-1 for N members with
/// a nonzero balance in a given currency) — see `PLAN.md` §2.
public enum Simplify {
    /// Runs the greedy match **once per currency** (currencies never net against
    /// each other — no FX) and concatenates the results in the order the
    /// currencies first appear in `balances`.
    ///
    /// Within a currency: repeatedly matches the largest creditor with the
    /// largest debtor, settles the smaller of the two amounts between them, and
    /// repeats until every balance is zero. Deterministic regardless of input
    /// ordering — ties between equal amounts are broken by `memberId`.
    public static func simplify(balances: [Balance]) -> [SimplifiedSettlement] {
        var currencyOrder: [String] = []
        var byCurrency: [String: [Balance]] = [:]
        for balance in balances {
            if byCurrency[balance.currency] == nil {
                byCurrency[balance.currency] = []
                currencyOrder.append(balance.currency)
            }
            byCurrency[balance.currency]!.append(balance)
        }

        return currencyOrder.flatMap { currency in
            simplifyOneCurrency(byCurrency[currency]!, currency: currency)
        }
    }

    private static func simplifyOneCurrency(_ balances: [Balance], currency: String) -> [SimplifiedSettlement] {
        var creditors: [(id: String, amount: Int64)] = []
        var debtors: [(id: String, amount: Int64)] = []

        for balance in balances {
            if balance.netMinor > 0 {
                creditors.append((balance.memberId, balance.netMinor))
            } else if balance.netMinor < 0 {
                debtors.append((balance.memberId, -balance.netMinor))
            }
        }

        sortDescending(&creditors)
        sortDescending(&debtors)

        var result: [SimplifiedSettlement] = []

        while !creditors.isEmpty && !debtors.isEmpty {
            var creditor = creditors.removeFirst()
            var debtor = debtors.removeFirst()

            let amount = min(creditor.amount, debtor.amount)
            result.append(
                SimplifiedSettlement(fromId: debtor.id, toId: creditor.id, amountMinor: amount, currency: currency)
            )

            creditor.amount -= amount
            debtor.amount -= amount

            if creditor.amount > 0 { creditors.append(creditor) }
            if debtor.amount > 0 { debtors.append(debtor) }

            sortDescending(&creditors)
            sortDescending(&debtors)
        }

        return result
    }

    /// Sorts largest amount first; ties broken by `memberId` for determinism.
    private static func sortDescending(_ items: inout [(id: String, amount: Int64)]) {
        items.sort { lhs, rhs in
            lhs.amount != rhs.amount ? lhs.amount > rhs.amount : lhs.id < rhs.id
        }
    }
}
