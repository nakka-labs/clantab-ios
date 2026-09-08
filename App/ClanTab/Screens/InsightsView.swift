import SwiftUI
import Charts
import ClanTabKit

/// Spending visualisations for a group — total, over time, by category, and by
/// member. All computation is `ClanTabKit.Insights` (pure); this view only lays
/// the results out. Reached from `GroupHomeView`; shows nothing but an empty
/// state until the group has at least one expense.
struct InsightsView: View {
    let expenses: [Expense]
    let members: [Member]
    /// For the shareable recap card's header (`CHECKLIST.md`).
    var groupName: String = "Your group"
    var groupEmoji: String?

    @State private var granularity: SpendGranularity = .month
    @State private var currency: String = ""
    /// The shareable recap card, rendered off-screen for the current currency.
    @State private var shareCard: Image?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var currencies: [String] { Insights.currencies(in: expenses) }
    private var total: Int64 { Insights.totalSpend(expenses, currency: currency) }
    private var byCategory: [CategorySpend] { Insights.byCategory(expenses, currency: currency) }
    private var byMember: [MemberSpend] { Insights.byMember(expenses, members: members, currency: currency) }
    private var overTime: [SpendBucket] { Insights.overTime(expenses, currency: currency, granularity: granularity) }

    var body: some View {
        Group {
            if expenses.isEmpty {
                ContentUnavailableView(
                    "No spending yet",
                    systemImage: "chart.bar",
                    description: Text("Add an expense to see where the money goes.")
                )
            } else {
                List {
                    if currencies.count > 1 {
                        Section {
                            Picker("Currency", selection: $currency) {
                                ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total spent").font(.subheadline).foregroundStyle(.secondary)
                            Text(money(total)).font(.system(.largeTitle, design: .rounded).weight(.semibold))
                        }
                    }

                    Section("Over time") {
                        Picker("Group by", selection: $granularity) {
                            Text("Day").tag(SpendGranularity.day)
                            Text("Week").tag(SpendGranularity.week)
                            Text("Month").tag(SpendGranularity.month)
                        }
                        .pickerStyle(.segmented)
                        overTimeChart
                    }

                    Section("By category") {
                        ForEach(byCategory) { entry in
                            breakdownRow(
                                title: entry.category.name,
                                icon: entry.category.symbolName,
                                amountMinor: entry.totalMinor
                            )
                        }
                    }

                    Section("By member") {
                        if spendingMembers.count > 1 {
                            memberDonut
                        }
                        ForEach(byMember) { entry in
                            breakdownRow(
                                title: entry.member.displayName,
                                icon: "person",
                                amountMinor: entry.totalMinor,
                                memberName: entry.member.displayName
                            )
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Surface.canvas)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareCard, !expenses.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: shareCard,
                        preview: SharePreview("\(groupName) — spending recap", image: shareCard)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if currency.isEmpty { currency = currencies.first ?? "" }
        }
        .task(id: currency) {
            guard !currency.isEmpty else { return }
            shareCard = RecapCard.render(RecapCard(
                groupName: groupName,
                groupEmoji: groupEmoji,
                members: members,
                content: .recap(totalMinor: total, byMember: byMember, currency: currency)
            ))
        }
    }

    private var overTimeChart: some View {
        Chart(overTime) { bucket in
            BarMark(
                x: .value("Period", bucket.start, unit: chartUnit),
                y: .value("Spent", Double(bucket.totalMinor) / 100)
            )
            .foregroundStyle(Color.accentColor)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let major = value.as(Double.self) {
                        Text(MoneyFormat.string(minorUnits: Int64(major * 100), currency: currency))
                    }
                }
            }
        }
        .frame(height: 180)
        .padding(.vertical, 4)
    }

    /// Members with a nonzero share of the spend in the selected currency —
    /// the donut's slices (and the check for whether a donut is worth showing:
    /// one slice is just a filled ring).
    private var spendingMembers: [MemberSpend] {
        byMember.filter { $0.totalMinor > 0 }
    }

    /// Spend-by-member as a donut (`CHECKLIST.md` "Insights donut chart, spend
    /// by member") — each slice in that member's `MemberColor`, matching the
    /// avatar and bar tint on the rows just below. The rows are the legend, so
    /// the chart's own is hidden.
    private var memberDonut: some View {
        Chart(spendingMembers) { entry in
            SectorMark(
                angle: .value("Spent", entry.totalMinor),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(by: .value("Member", entry.member.displayName))
        }
        .chartForegroundStyleScale(
            domain: spendingMembers.map { $0.member.displayName },
            range: spendingMembers.map { MemberColor.color(for: $0.member.displayName) }
        )
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(.vertical, 8)
        .accessibilityLabel("Spending by member")
        .accessibilityValue(
            spendingMembers
                .map { "\($0.member.displayName) \(money($0.totalMinor))" }
                .joined(separator: ", ")
        )
    }

    private var chartUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    /// A category/member row: icon, name, a proportional bar, and the amount.
    /// Pass `memberName` for a member row — it gets that member's identity
    /// avatar and tints the bar with their `MemberColor`.
    private func breakdownRow(title: String, icon: String, amountMinor: Int64, memberName: String? = nil) -> some View {
        let fraction = total > 0 ? Double(amountMinor) / Double(total) : 0
        let tint = memberName.map { MemberColor.color(for: $0) } ?? Color.accentColor

        let name = Group {
            if let memberName {
                HStack(spacing: 8) {
                    MemberAvatar(name: memberName, size: 22)
                    Text(title)
                }
            } else {
                Label(title, systemImage: icon)
            }
        }
        let amount = Text(money(amountMinor))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)

        return VStack(alignment: .leading, spacing: 6) {
            // The amount drops under the name at accessibility text sizes
            // rather than being truncated off the right edge.
            if dynamicTypeSize.isAccessibilitySize {
                name
                amount
            } else {
                HStack { name; Spacer(minLength: 8); amount }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Surface.well)
                    Capsule().fill(tint)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(money(amountMinor)), \(Int((fraction * 100).rounded())) percent")
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.string(minorUnits: minor, currency: currency)
    }
}
