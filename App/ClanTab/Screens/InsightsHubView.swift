import SwiftUI
import Charts
import ClanTabKit

/// The global Insights tab — personal, cross-group data and graphs
/// (`CHECKLIST.md` "Insights tab must show personal data, not a groups
/// list"): overall owe/owed totals, and your own spend by category,
/// aggregated across every group you're in. Reworked 2026-09-13 from the
/// build-9 audit's "every known group in one list, tap one to drill into
/// its own spend charts" design — a real-device report called that out as
/// backwards: this tab should be personal data, not a second groups list
/// that leads into per-group data. A specific group's own spend/category/
/// member charts now live on that group's own page instead
/// (`GroupHomeView`'s "View Insights", added the same day) — this tab
/// deliberately never navigates into one.
struct InsightsHubView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel

    @State private var groups: [KnownGroup] = []
    @State private var contributions: [PersonalInsights.GroupContribution] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var currency = ""
    @State private var scrubbedCategoryAngle: Double?

    private var chartableGroups: [KnownGroup] {
        groups.filter { !$0.isArchived && !$0.isHidden }
    }

    private var currencies: [String] { PersonalInsights.currencies(in: contributions) }
    private var total: Int64 { currency.isEmpty ? 0 : PersonalInsights.totalSpend(contributions, currency: currency) }
    private var byCategory: [CategorySpend] {
        currency.isEmpty ? [] : PersonalInsights.byCategory(contributions, currency: currency)
    }
    private var scrubbedCategory: CategorySpend? {
        guard let scrubbedCategoryAngle else { return nil }
        var accumulated: Double = 0
        for entry in byCategory {
            accumulated += Double(entry.totalMinor)
            if scrubbedCategoryAngle <= accumulated { return entry }
        }
        return byCategory.last
    }

    var body: some View {
        List {
            // The same cross-group owe/owed summary the dashboard's own
            // header shows — renders nothing until balances have loaded or
            // every currency nets to zero.
            if !chartableGroups.isEmpty {
                Section {
                    DashboardTotalsHeader(groups: chartableGroups)
                }
                .listRowBackground(Color.clear)
            }

            if chartableGroups.isEmpty {
                ContentUnavailableView {
                    Label { Text("Nothing to Chart Yet") } icon: {
                        Image("EmptyStateGlyph").renderingMode(.template)
                    }
                } description: {
                    Text("Add some expenses to a group and your personal spending breakdown shows up here.")
                }
            } else if isLoading, contributions.isEmpty {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
            } else {
                if currencies.count > 1 {
                    Section {
                        Picker("Currency", selection: $currency) {
                            ForEach(currencies, id: \.self) { code in Text(code).tag(code) }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if !currency.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("You spent").font(.subheadline).foregroundStyle(.secondary)
                            Text(money(total)).font(.display(size: 34, weight: .semibold, relativeTo: .largeTitle))
                        }
                    }

                    if !byCategory.isEmpty {
                        Section("By category") {
                            if byCategory.count > 1 {
                                categoryPie
                            }
                            ForEach(byCategory) { entry in
                                breakdownRow(entry)
                            }
                        }
                    }
                }

                // Per-group balances — still personal data (what *you* owe
                // or are owed in each group), just broken out by group; not
                // a navigation list into that group's own spend charts (see
                // this view's own doc comment).
                Section("By group") {
                    ForEach(chartableGroups) { group in
                        groupRow(group)
                    }
                }
            }

            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Insights")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func groupRow(_ group: KnownGroup) -> some View {
        HStack(spacing: 12) {
            if let emoji = group.emoji, !emoji.isEmpty {
                Text(emoji).font(.body)
                    .frame(width: 32, height: 32)
                    .background(GroupColor.color(forId: group.groupId).opacity(0.18), in: Circle())
            } else {
                Text(GroupsListView.initial(for: group))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(GroupColor.badge(forId: group.groupId), in: Circle())
            }
            Text(group.name.isEmpty ? "Group" : group.name)
            Spacer()
            if let line = GroupsListView.balanceLine(for: group) {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var categoryPie: some View {
        Chart(byCategory) { entry in
            SectorMark(angle: .value("Spent", entry.totalMinor), angularInset: 1.5)
                .cornerRadius(3)
                .foregroundStyle(by: .value("Category", entry.category.name))
                .opacity(scrubbedCategory == nil || scrubbedCategory?.id == entry.id ? 1 : 0.3)
        }
        .chartAngleSelection(value: $scrubbedCategoryAngle)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let category = scrubbedCategory, let plotAnchor = proxy.plotFrame {
                    let plot = geo[plotAnchor]
                    categoryTooltip(for: category)
                        .position(x: plot.midX, y: plot.midY)
                }
            }
        }
        .chartForegroundStyleScale(
            domain: byCategory.map { $0.category.name },
            range: byCategory.map { $0.category.pastelColor }
        )
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(.vertical, 8)
        .animation(.easeOut(duration: 0.15), value: scrubbedCategory)
        .accessibilityLabel("Spending by category, across every group")
        .accessibilityValue(
            byCategory.map { "\($0.category.name) \(money($0.totalMinor))" }.joined(separator: ", ")
        )
    }

    private func categoryTooltip(for category: CategorySpend) -> some View {
        VStack(spacing: 2) {
            Text(category.category.name).font(.caption).foregroundStyle(.secondary)
            Text(money(category.totalMinor)).font(.headline)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(false)
    }

    private func breakdownRow(_ entry: CategorySpend) -> some View {
        let fraction = total > 0 ? Double(entry.totalMinor) / Double(total) : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(entry.category.name, systemImage: entry.category.symbolName)
                Spacer(minLength: 8)
                Text(money(entry.totalMinor)).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Surface.well)
                    Capsule().fill(entry.category.pastelColor)
                        .frame(width: max(0, geo.size.width * fraction))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.category.name), \(money(entry.totalMinor)), \(Int((fraction * 100).rounded())) percent")
    }

    private func money(_ minor: Int64) -> String {
        MoneyFormat.string(minorUnits: minor, currency: currency)
    }

    /// Refreshes the cached per-group balance list (cheap, local) and — the
    /// heavier half — fetches every known group's full state so
    /// `PersonalInsights` has real expenses to aggregate. Best-effort: a
    /// group that fails to load is silently dropped from the aggregate
    /// rather than failing the whole tab, same shape as this app's other
    /// fan-out reads (`handleAuthFriends`'s cross-group aggregation).
    private func reload() async {
        groups = knownGroups.all()
        guard !chartableGroups.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        let myMemberIds = Dictionary(uniqueKeysWithValues: auth.groups.map { ($0.groupId, $0.memberId) })
        let fetched: [PersonalInsights.GroupContribution?] = await withTaskGroup(of: PersonalInsights.GroupContribution?.self) { taskGroup in
            for group in chartableGroups {
                guard let myMemberId = myMemberIds[group.groupId] else { continue }
                taskGroup.addTask {
                    guard let state = try? await client.fetchGroupState(groupId: group.groupId, accessToken: group.accessToken) else {
                        return nil
                    }
                    return PersonalInsights.GroupContribution(groupId: group.groupId, myMemberId: myMemberId, expenses: state.expenses)
                }
            }
            var results: [PersonalInsights.GroupContribution?] = []
            for await result in taskGroup { results.append(result) }
            return results
        }
        contributions = fetched.compactMap { $0 }
        if currency.isEmpty { currency = currencies.first ?? "" }
    }
}
