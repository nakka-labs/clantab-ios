import SwiftUI
import WidgetKit
import ClanTabKit

/// Small-widget-only for v1 (`FEATURE_BACKLOG.md`) — one glanceable number,
/// SF Rounded per the portfolio hero-numeral treatment (`DESIGN_BIBLE.md`).
struct BalanceWidgetView: View {
    let entry: BalanceEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(for: snapshot)
            } else {
                emptyState
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private func content(for snapshot: WidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.groupName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let headline = Balances.headline(snapshot.balances) {
                Text(MoneyFormat.string(minorUnits: abs(headline.netMinor), currency: headline.currency))
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(headline.netMinor < 0 ? "you owe" : "you're owed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("All settled up")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Open ClanTab to get started")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}
