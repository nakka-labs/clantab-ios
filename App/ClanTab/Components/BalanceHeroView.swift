import SwiftUI
import ClanTabKit

/// The "You are owed ₹1,200" / "You owe ₹350" hero card on Group Home. With
/// multi-currency a member can be owed in one currency and owe in another, so
/// each currency gets its own line and they're never blended.
struct BalanceHeroView: View {
    /// The current member's nonzero balances, one per currency.
    let balances: [Balance]

    var body: some View {
        VStack(spacing: 8) {
            if balances.isEmpty {
                Text("You're all settled up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(balances.count == 1 ? headline(for: balances[0]) : "Your balance")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(balances, id: \.currency) { balance in
                        Text(amountLine(for: balance))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .foregroundStyle(balance.netMinor > 0 ? .green : .red)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .accessibilityElement(children: .combine)
    }

    private func headline(for balance: Balance) -> String {
        balance.netMinor > 0 ? "You are owed" : "You owe"
    }

    /// For a single currency the sign is carried by the headline, so show the
    /// bare amount; for multiple, prefix each so a mixed row still reads.
    private func amountLine(for balance: Balance) -> String {
        let amount = MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency)
        guard balances.count > 1 else { return amount }
        return balance.netMinor > 0 ? "owed \(amount)" : "owe \(amount)"
    }
}
