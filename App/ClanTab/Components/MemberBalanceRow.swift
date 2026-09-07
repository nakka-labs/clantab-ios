import SwiftUI
import ClanTabKit

/// One row in Group Home's member list: a name and their net balance in each
/// currency they have activity in (nonzero only; blank = settled up).
struct MemberBalanceRow: View {
    let member: Member
    /// This member's nonzero balances, one per currency.
    let balances: [Balance]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: dynamicTypeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
            MemberAvatar(member, size: 28)
            // At accessibility text sizes the balance stacks under the name
            // rather than being squeezed off the right edge.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.displayName)
                    balanceText(alignment: .leading)
                }
            } else {
                Text(member.displayName)
                Spacer(minLength: 8)
                balanceText(alignment: .trailing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private func balanceText(alignment: HorizontalAlignment) -> some View {
        if balances.isEmpty {
            Text("settled").foregroundStyle(.secondary)
        } else {
            VStack(alignment: alignment, spacing: 2) {
                ForEach(balances, id: \.currency) { balance in
                    Text(MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency))
                        .foregroundStyle(balance.netMinor > 0 ? .green : .red)
                        .lineLimit(1)
                }
            }
        }
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
