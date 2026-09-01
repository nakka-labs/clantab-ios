import SwiftUI
import ClanTabKit

/// One row in Group Home's member list: a name and their net balance in each
/// currency they have activity in (nonzero only; blank = settled up).
struct MemberBalanceRow: View {
    let member: Member
    /// This member's nonzero balances, one per currency.
    let balances: [Balance]

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(member.displayName)
            Spacer()
            if balances.isEmpty {
                Text("settled").foregroundStyle(.secondary)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    ForEach(balances, id: \.currency) { balance in
                        Text(MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency))
                            .foregroundStyle(balance.netMinor > 0 ? .green : .red)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        if balances.isEmpty { return "\(member.displayName), settled up" }
        let parts = balances.map { balance -> String in
            let amount = MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency)
            return balance.netMinor > 0 ? "is owed \(amount)" : "owes \(amount)"
        }
        return "\(member.displayName) \(parts.joined(separator: ", and "))"
    }
}
