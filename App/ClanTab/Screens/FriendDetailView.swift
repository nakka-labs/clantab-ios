import SwiftUI
import ClanTabKit

/// One friend's detail (`CHECKLIST.md` "Friends/contacts list... + private
/// 1:1 tabs") — the net balance across every group shared with them, the
/// private 1:1 tab (started or reopened here, lazily — no invite/join
/// ceremony), and which formal groups that balance is drawn from.
struct FriendDetailView: View {
    let friend: Friend
    let auth: AuthViewModel
    let onOpenGroup: (String) -> Void

    @State private var isOpeningTab = false
    @State private var errorMessage: String?

    /// The formal groups this balance is drawn from — the private tab (once
    /// it exists) gets its own section below, not listed again here.
    private var sharedGroups: [FriendGroup] {
        friend.groups.filter { !$0.hidden }
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
                Text(PeopleView.summary(friend.net, name: friend.displayName))
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

            if !sharedGroups.isEmpty {
                Section("Shared Groups") {
                    ForEach(sharedGroups) { group in
                        Text(group.groupName)
                    }
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(friend.displayName)
        .navigationBarTitleDisplayMode(.inline)
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
