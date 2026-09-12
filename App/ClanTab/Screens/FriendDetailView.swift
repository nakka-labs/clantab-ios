import SwiftUI
import ClanTabKit

/// One friend's detail (`CHECKLIST.md` "Friends/contacts list... + private
/// 1:1 tabs") — the net balance across every group shared with them, a
/// per-group breakdown with a one-tap "Settle All" (`CHECKLIST.md` UX audit
/// [8] — folded in from the old standalone "Settle Across Groups" screen),
/// the private 1:1 tab (started or reopened here, lazily — no invite/join
/// ceremony), and which formal groups that balance is drawn from.
struct FriendDetailView: View {
    let friend: Friend
    let auth: AuthViewModel
    let onOpenGroup: (String) -> Void

    /// The per-group breakdown, fetched separately — `Friend.groups` only
    /// carries group identity, not amounts (`peopleAcrossGroups` is the one
    /// endpoint that does, but it's nonzero-only, so a settled friend has no
    /// entry here and `edges` stays `[]`, same as `Balance` reads "Settled
    /// up"). `nil` while loading.
    @State private var edges: [CrossGroupEdge]?
    @State private var isSettling = false
    @State private var isOpeningTab = false
    @State private var errorMessage: String?

    /// The formal groups this balance is drawn from — the private tab (once
    /// it exists) gets its own section below, not listed again here.
    private var sharedGroups: [FriendGroup] {
        friend.groups.filter { !$0.hidden }
    }

    /// The net to show in "Balance" — derived from the freshly-reloaded
    /// `edges` once they're in hand, not the static `friend.net` the
    /// Friends list passed in at push time. Without this, settling here
    /// would leave the "By Group" row saying "Settled up" right underneath
    /// a "Balance" line that still says otherwise until the screen is
    /// reopened.
    private var currentNet: [CrossGroupNet] {
        guard let edges else { return friend.net }
        var byCurrency: [String: Int64] = [:]
        for edge in edges {
            byCurrency[edge.currency, default: 0] += edge.youPay ? edge.amountMinor : -edge.amountMinor
        }
        return byCurrency.map { CrossGroupNet(currency: $0.key, netMinor: $0.value) }
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    MemberAvatar(name: friend.displayName, size: 56)
                    Text(friend.displayName)
                        .font(.title2.weight(.semibold))
                        .lineLimit(2)
                }
                .padding(.vertical, 4)
                .listRowBackground(Color.clear)
            }

            Section("Balance") {
                Text(CrossGroupSummary.line(currentNet, name: friend.displayName))
            }

            if !sharedGroups.isEmpty {
                Section("By Group") {
                    ForEach(sharedGroups) { group in
                        HStack {
                            Text(group.groupName)
                            Spacer()
                            if let edge = edges?.first(where: { $0.groupId == group.groupId }) {
                                Text(directionText(edge)).foregroundStyle(.secondary)
                            } else if edges != nil {
                                Text("Settled up").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let edges, !edges.isEmpty {
                Section {
                    Button {
                        Task { await settleAll(edges) }
                    } label: {
                        if isSettling { ProgressView() } else { Text("Settle All") }
                    }
                    .disabled(isSettling)
                } footer: {
                    Text("Records a settlement in each group. This can't be undone from here.")
                }
            }

            Section {
                Button {
                    Task { await openTab() }
                } label: {
                    HStack {
                        Label(
                            friend.existingTabGroupId != nil ? "Open Private Tab" : "Start a Private Tab",
                            systemImage: "person.2"
                        )
                        if isOpeningTab {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isOpeningTab)
            } footer: {
                Text("Just between you and \(friend.displayName) — its own running tally, separate from any group you share.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadEdges() }
    }

    private func directionText(_ edge: CrossGroupEdge) -> String {
        let amount = MoneyFormat.string(minorUnits: edge.amountMinor, currency: edge.currency)
        return edge.youPay ? "you pay \(amount)" : "pays you \(amount)"
    }

    /// Finds this friend's own entry in the nonzero-only cross-group people
    /// list — `nil` (never found) reads the same as "fully settled," not an
    /// error, so no error message is shown when this simply comes back
    /// empty.
    private func loadEdges() async {
        let people = await auth.peopleAcrossGroups()
        edges = people?.first(where: { $0.id == friend.id })?.groups ?? []
    }

    private func settleAll(_ edges: [CrossGroupEdge]) async {
        isSettling = true
        errorMessage = nil
        defer { isSettling = false }
        let failed = await auth.settleAll(edges)
        if failed > 0 {
            errorMessage = "\(failed) group\(failed == 1 ? "" : "s") couldn't be settled — try again."
        }
        await loadEdges()
    }

    private func openTab() async {
        isOpeningTab = true
        errorMessage = nil
        defer { isOpeningTab = false }
        if let groupId = await auth.ensureFriendTab(friend) {
            onOpenGroup(groupId)
        } else {
            errorMessage = "Couldn't open the private tab. Try again."
        }
    }
}
