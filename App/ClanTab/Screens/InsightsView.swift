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
    /// Drag position over the over-time chart (`CHECKLIST.md` "Chart
    /// interaction") — `nil` when not scrubbing.
    @State private var scrubbedDate: Date?
    /// Angle scrubbed on the by-member donut, resolved to a slice.
    @State private var scrubbedAngle: Double?
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
                    "Nothing to Chart Yet",
                    image: "EmptyStateGlyph",
                    description: Text("Once the group logs a few expenses, this is where the totals, trends, and who-paid-what breakdowns show up.")
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
                            Text(money(total)).font(.display(size: 34, weight: .semibold, relativeTo: .largeTitle))
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

    /// The bar nearest the current scrub position.
    private var scrubbedBucket: SpendBucket? {
        guard let scrubbedDate else { return nil }
        return overTime.min {
            abs($0.start.timeIntervalSince(scrubbedDate)) < abs($1.start.timeIntervalSince(scrubbedDate))
        }
    }

    private var overTimeChart: some View {
        Chart(overTime) { bucket in
            BarMark(
                x: .value("Period", bucket.start, unit: chartUnit),
                y: .value("Spent", Double(bucket.totalMinor) / 100)
            )
            // Native gradient fill (`CHECKLIST.md` "gradient fills") — the
            // accent from full at the top fading down.
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accentColor, Color.accentColor.opacity(0.4)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .cornerRadius(5)
            // Dim the other bars while scrubbing so the touched one stands out.
            .opacity(scrubbedBucket == nil || scrubbedBucket?.id == bucket.id ? 1 : 0.3)
        }
        .chartXSelection(value: $scrubbedDate)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let bucket = scrubbedBucket,
                   let plotAnchor = proxy.plotFrame,
                   let x = proxy.position(forX: bucket.start) {
                    let plot = geo[plotAnchor]
                    scrubTooltip(for: bucket)
                        .position(x: plot.origin.x + x, y: 8)
                }
            }
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
        .animation(.easeOut(duration: 0.15), value: scrubbedBucket)
    }

    /// The little "Sep · ₹4,200" label that follows the scrub over the bar chart.
    private func scrubTooltip(for bucket: SpendBucket) -> some View {
        VStack(spacing: 1) {
            Text(bucket.start, format: scrubDateFormat)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(money(bucket.totalMinor))
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .fixedSize()
    }

    private var scrubDateFormat: Date.FormatStyle {
        switch granularity {
        case .day: return .dateTime.month(.abbreviated).day()
        case .week: return .dateTime.month(.abbreviated).day()
        case .month: return .dateTime.month(.wide).year()
        }
    }

    /// Members with a nonzero share of the spend in the selected currency —
    /// the donut's slices (and the check for whether a donut is worth showing:
    /// one slice is just a filled ring).
    private var spendingMembers: [MemberSpend] {
        byMember.filter { $0.totalMinor > 0 }
    }

    /// The slice under the current donut scrub angle.
    private var scrubbedMember: MemberSpend? {
        guard let scrubbedAngle else { return nil }
        var cumulative = 0.0
        for entry in spendingMembers {
            cumulative += Double(entry.totalMinor)
            if scrubbedAngle <= cumulative { return entry }
        }
        return spendingMembers.last
    }

    /// Spend-by-member as a donut (`CHECKLIST.md` "Insights donut chart, spend
    /// by member") — each slice in that member's `MemberColor`, matching the
    /// avatar and bar tint on the rows just below. The rows are the legend, so
    /// the chart's own is hidden. Drag around the ring to isolate a slice
    /// (`CHECKLIST.md` "Chart interaction").
    private var memberDonut: some View {
        Chart(spendingMembers) { entry in
            SectorMark(
                angle: .value("Spent", entry.totalMinor),
                innerRadius: .ratio(0.6),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(by: .value("Member", entry.member.displayName))
            .opacity(scrubbedMember == nil || scrubbedMember?.id == entry.id ? 1 : 0.3)
        }
        .chartAngleSelection(value: $scrubbedAngle)
        .chartBackground { _ in
            VStack(spacing: 1) {
                if let m = scrubbedMember {
                    Text(m.member.displayName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Text(money(m.totalMinor)).font(.headline).monospacedDigit()
                } else {
                    Text("Total").font(.caption).foregroundStyle(.secondary)
                    Text(money(total)).font(.headline).monospacedDigit()
                }
            }
            .padding(.horizontal, 8)
        }
        .chartForegroundStyleScale(
            domain: spendingMembers.map { $0.member.displayName },
            range: spendingMembers.map { MemberColor.color(for: $0.member.displayName) }
        )
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.15), value: scrubbedMember)
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
