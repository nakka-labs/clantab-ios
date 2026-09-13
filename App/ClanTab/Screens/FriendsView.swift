import SwiftUI
import ClanTabKit

/// The friends directory (`CHECKLIST.md` "Friends/contacts list... + private
/// 1:1 tabs") — every other claimed person the caller shares a group with,
/// regardless of balance. A top-level tab (`CHECKLIST.md` UX audit [6]).
/// Tapping a friend opens `FriendDetailView`, which is also where a private
/// 1:1 tab is started or reopened.
struct FriendsView: View {
    let auth: AuthViewModel
    let onOpenGroup: (String) -> Void

    @State private var friends: [Friend]?
    @State private var loadError: String?

    var body: some View {
        List {
            if let friends {
                if friends.isEmpty {
                    // The old copy ("share a group and they'll show up
                    // here") was actively misleading — only a co-member who
                    // has signed in themselves ever appears (`peerSettlements`
                    // only surfaces a linked identity, by design; a member
                    // added by typed name alone never counts until they
                    // claim it). A playtester in several groups full of
                    // people still saw a bare empty state and read it as
                    // broken, not "nobody's signed in yet" (`CHECKLIST.md`
                    // "Friend playtest, round 3").
                    ContentUnavailableView(
                        "No Friends Yet",
                        image: "EmptyStateGlyph",
                        description: Text("Nobody in your groups has signed into ClanTab yet — only people who have show up here, settled up or not. Share your group's invite link (from Group Options) so they can join.")
                    )
                } else {
                    // A lone row (or a short list of them) otherwise leaves the
                    // rest of the screen blank with nothing explaining what
                    // "Friends" even means here — unlike every other
                    // lightly-populated screen in the app ("No Expenses Yet,"
                    // the CSV import picker), which pairs empty space with a
                    // sentence of context (`CHECKLIST.md` UX audit fresh-eyes-
                    // pass [4]). A footer works for any list length, not just
                    // a short one, so it's shown regardless of count.
                    Section {
                        ForEach(friends) { friend in
                            NavigationLink {
                                FriendDetailView(friend: friend, auth: auth, onOpenGroup: onOpenGroup)
                            } label: {
                                row(friend)
                            }
                        }
                    } footer: {
                        Text("Anyone who's signed into ClanTab and shares a group with you, settled up or not — someone who hasn't signed in yet won't appear until they do. Tap someone for your shared history across groups, or to start a private 1:1 tab.")
                    }
                }
            } else if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            } else {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle("Friends")
        .task { if friends == nil { await reload() } }
        .refreshable { await reload() }
    }

    private func reload() async {
        if let loaded = await auth.friends() {
            friends = loaded
            loadError = nil
        } else if friends == nil {
            loadError = "Couldn't load your friends. Pull to refresh to try again."
        }
    }

    @ViewBuilder
    private func row(_ friend: Friend) -> some View {
        HStack(spacing: 12) {
            MemberAvatar(name: friend.displayName, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.displayName).font(.headline)
                Text(CrossGroupSummary.line(friend.net, name: friend.displayName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
