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
    let currency: String

    @State private var granularity: SpendGranularity = .month

    private var total: Int64 { Insights.totalSpend(expenses) }
    private var byCategory: [CategorySpend] { Insights.byCategory(expenses) }
    private var byMember: [MemberSpend] { Insights.byMember(expenses, members: members) }
    private var overTime: [SpendBucket] { Insights.overTime(expenses, granularity: granularity) }

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
                        ForEach(byMember) { entry in
                            breakdownRow(
                                title: entry.member.displayName,
                                icon: "person",
                                amountMinor: entry.totalMinor
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
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

    private var chartUnit: Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    /// A category/member row: icon, name, a proportional bar, and the amount.
    private func breakdownRow(title: String, icon: String, amountMinor: Int64) -> some View {
        let fraction = total > 0 ? Double(amountMinor) / Double(total) : 0

        return VStack(spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Text(money(amountMinor)).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    Capsule().fill(Color.accentColor)
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
