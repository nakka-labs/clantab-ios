import SwiftUI
import SquareKit

/// The "You are owed ₹1,200" / "You owe ₹350" hero card on Group Home.
struct BalanceHeroView: View {
    let balance: Balance
    let currency: String

    var body: some View {
        VStack(spacing: 8) {
            Text(headline)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
            if balance.netMinor != 0 {
                Text(MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: currency))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(balance.netMinor > 0 ? .green : .red)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var headline: String {
        if balance.netMinor > 0 { return "You are owed" }
        if balance.netMinor < 0 { return "You owe" }
        return "You're all settled up"
    }
}
