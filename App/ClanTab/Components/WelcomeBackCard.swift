import ClanTabKit
import SwiftUI

/// "Welcome back — here's where things stand" — a one-time callout on the
/// dashboard after a gap since the last open (`CHECKLIST.md` "Returning-user
/// balance summary"), reusing `DashboardTotals`/`DashboardTotalsHeader`'s own
/// per-currency line so the figure always matches the always-on header below
/// it. Renders nothing once every currency nets to zero (fully settled up —
/// nothing to report back).
struct WelcomeBackCard: View {
    let groups: [KnownGroup]
    let onDismiss: () -> Void

    private var totals: [DashboardTotals.CurrencyTotal] { DashboardTotals.compute(groups) }

    var body: some View {
        if !totals.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Label("Welcome back", systemImage: "hand.wave.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(6)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss")
                }
                Text("Here's where things stand:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ForEach(totals, id: \.currency) { total in
                    Text(DashboardTotalsHeader.line(for: total))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(total.netMinor > 0 ? .green : .red)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Surface.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
}
