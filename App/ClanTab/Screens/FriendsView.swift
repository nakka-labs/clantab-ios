import SwiftUI
import ClanTabKit

/// The friends directory (`CHECKLIST.md` "Friends/contacts list... + private
/// 1:1 tabs") — every other claimed person the caller shares a group with,
/// regardless of balance. Reached from a toolbar button on `StartView`, next
/// to Settings. Tapping a friend opens `FriendDetailView`, which is also
/// where a private 1:1 tab is started or reopened.
struct FriendsView: View {
    let auth: AuthViewModel
    let onOpenGroup: (String) -> Void
    let onDone: () -> Void

    @State private var friends: [Friend]?
    @State private var loadError: String?

    var body: some View {
        List {
            if let friends {
                if friends.isEmpty {
                    ContentUnavailableView(
                        "No Friends Yet",
                        image: "EmptyStateGlyph",
                        description: Text("Share a group with someone and they'll show up here — settled up or not.")
                    )
                } else {
                    ForEach(friends) { friend in
                        NavigationLink {
                            FriendDetailView(friend: friend, auth: auth, onOpenGroup: onOpenGroup)
                        } label: {
                            row(friend)
                        }
                    }
                }
            } else if let loadError {
                Section { Text(loadError).foregroundStyle(.red) }
            } else {
                Section { HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) } }
            }
        }
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done", action: onDone) }
        }
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
                Text(PeopleView.summary(friend.net, name: friend.displayName))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
