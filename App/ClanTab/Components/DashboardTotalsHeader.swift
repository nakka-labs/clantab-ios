import ClanTabKit
import SwiftUI

/// The cross-group balance summary above the dashboard's groups list
/// (`CHECKLIST.md` "Currency-bucketed totals header on the dashboard") — one
/// line per currency, "You owe ₹500" / "You're owed $20", never blended into
/// a single number. Renders nothing when every currency nets to zero, or
/// before any group's balances have loaded.
struct DashboardTotalsHeader: View {
    let groups: [KnownGroup]

    private var totals: [DashboardTotals.CurrencyTotal] { DashboardTotals.compute(groups) }

    var body: some View {
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("YOUR BALANCE")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 3)
                ForEach(totals, id: \.currency) { total in
                    Text(Self.line(for: total))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(total.netMinor > 0 ? .green : .red)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .combine)
        }
    }

    /// "You owe ₹500" / "You're owed $20" for one currency bucket. Internal +
    /// `static` so `DashboardTotalsHeaderTests` can check the string directly.
    nonisolated static func line(for total: DashboardTotals.CurrencyTotal) -> String {
        let amount = MoneyFormat.string(minorUnits: abs(total.netMinor), currency: total.currency)
        return total.netMinor < 0 ? "You owe \(amount)" : "You're owed \(amount)"
    }
}
