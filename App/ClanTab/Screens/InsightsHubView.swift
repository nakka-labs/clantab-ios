import SwiftUI
import ClanTabKit

/// Insights promoted to a top-level tab (`CHECKLIST.md` UX audit [6] step 1)
/// — previously a row one tap inside each group, now a global entry point:
/// every known group, tap one to drill into its own `InsightsView`. A genuine
/// blended cross-group chart (spend across every group on one graph) is a
/// separate, bigger feature with no backend aggregate to draw on yet — same
/// call as the dashboard's parked "cross-group spend graphs" item; this hub
/// is the "global view, drills into per-group detail" the audit actually
/// asked for, not a promise of blended charts.
struct InsightsHubView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring

    @State private var groups: [KnownGroup] = []

    private var chartableGroups: [KnownGroup] {
        groups.filter { !$0.isArchived && !$0.isHidden }
    }

    var body: some View {
        List {
            if chartableGroups.isEmpty {
                ContentUnavailableView {
                    Label { Text("Nothing to Chart Yet") } icon: {
                        Image("EmptyStateGlyph").renderingMode(.template)
                    }
                } description: {
                    Text("Add some expenses to a group and its spending breakdown shows up here.")
                }
            } else {
                Section("Your Groups") {
                    ForEach(chartableGroups) { group in
                        NavigationLink {
                            GroupInsightsLoader(group: group, client: client)
                        } label: {
                            row(for: group)
                        }
                    }
                }
            }
        }
        .navigationTitle("Insights")
        .task { groups = knownGroups.all() }
        .refreshable { groups = knownGroups.all() }
    }

    private func row(for group: KnownGroup) -> some View {
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
        }
    }
}

/// Fetches one group's full state on push, then hands it to the existing
/// per-group `InsightsView` — the drill-in half of `InsightsHubView`.
private struct GroupInsightsLoader: View {
    let group: KnownGroup
    let client: ClanTabClient

    @State private var state: GroupStateResponse?
    @State private var loadError: String?

    var body: some View {
        Group {
            if let state {
                InsightsView(
                    expenses: state.expenses,
                    members: state.members,
                    groupName: state.group.name,
                    groupEmoji: state.group.emoji
                )
            } else if let loadError {
                ContentUnavailableView(
                    "Couldn't Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError)
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle(group.name.isEmpty ? "Group" : group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                state = try await client.fetchGroupState(groupId: group.groupId, accessToken: group.accessToken)
            } catch {
                loadError = friendlyMessage(for: error)
            }
        }
    }
}
