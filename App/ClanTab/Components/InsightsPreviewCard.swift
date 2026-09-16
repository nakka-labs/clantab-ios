import ClanTabKit
import SwiftUI

/// A compact "Total spent" summary for Group Home's swipeable hero page
/// (`CHECKLIST.md`, build-16 real-device finding) — the full `InsightsView`
/// (pie chart, category breakdown, granularity picker) needs real scroll
/// room, so it's presented as a sheet from "See Insights" rather than
/// crammed into the ~250pt hero strip, where it used to fight the hero
/// `TabView`'s own swipe gesture with its own internal scroll.
struct InsightsPreviewCard: View {
    let expenses: [Expense]
    let onSeeInsights: () -> Void

    private var currency: String { Insights.currencies(in: expenses).first ?? "" }
    private var total: Int64 { Insights.totalSpend(expenses, currency: currency) }
    private var topCategory: CategorySpend? { Insights.byCategory(expenses, currency: currency).first }

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("Total spent")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(MoneyFormat.string(minorUnits: total, currency: currency))
                    .font(.system(size: 30, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            if let topCategory {
                Label("Most on \(topCategory.category.name)", systemImage: topCategory.category.symbolName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button(action: onSeeInsights) {
                Label("See Insights", systemImage: "chart.pie")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
