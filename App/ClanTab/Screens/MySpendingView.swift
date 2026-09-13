import SwiftUI
import Charts
import ClanTabKit

/// Personal, cross-group spending — the one piece of the old Insights tab
/// that wasn't a duplicate of Home's own dashboard (`CHECKLIST.md` D14):
/// your own spend by category, aggregated across every group you're in.
/// Reached from Settings, not a tab of its own — a single screen doesn't
/// need the real estate a whole tab costs, especially for a feature with no
/// demonstrated demand beyond this one figure (the same reasoning that
/// removed the Insights tab in the first place, `RootView`'s own note where
/// that tab used to be).
///
/// Deliberately does **not** repeat the cross-group owe/owed total or the
/// per-group balance list `InsightsHubView` used to show — `StartView`'s
/// dashboard already covers both; this screen is only the part that was
/// genuinely unique. Reuses `PersonalInsights`/`CategorySpend` (kit) and the
/// same chart/row code `InsightsHubView` had, including both fixes from its
/// "insights completely removed" bug (`CHECKLIST.md` D6 / "Real-device
/// findings, builds 11/12" — the `uniquingKeysWith` dictionary build and the
/// `auth.groups`-load race's `.onChange`) — this screen depends on both
/// exactly as much as the view it replaces did.
struct MySpendingView: View {
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
            }

            if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            }
        }
        .navigationTitle("My Spending")
        .task { await reload() }
        // See this view's own doc comment — the exact race `InsightsHubView`
        // hit (`CHECKLIST.md` D6): `auth.groups` resolves from its own
        // network round-trip, and if this screen's `.task` ran first, every
        // group was silently skipped with nothing left to re-trigger the
        // aggregation.
        .onChange(of: auth.groups) { _, _ in Task { await reload() } }
        .refreshable { await reload() }
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
    /// rather than failing the whole screen, same shape as this app's other
    /// fan-out reads (`handleAuthFriends`'s cross-group aggregation).
    private func reload() async {
        groups = knownGroups.all()
        guard !chartableGroups.isEmpty else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        // `uniquingKeysWith` rather than `uniqueKeysWithValues:` — the
        // latter *traps* on a duplicate key, and this dictionary is built
        // from network-sourced data; never take that risk regardless of
        // how confident the current server logic is about uniqueness.
        let myMemberIds = Dictionary(auth.groups.map { ($0.groupId, $0.memberId) }, uniquingKeysWith: { _, new in new })
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
        // Loaded, but came back with nothing to chart even though there are
        // known groups — either every fetch failed (offline, a stale
        // token) or `auth.groups` hadn't resolved a member id for any of
        // them yet. Say so rather than silently showing an empty screen with
        // no explanation.
        if contributions.isEmpty {
            loadError = "Couldn't load your personal spending. Pull to refresh to try again."
        }
    }
}
