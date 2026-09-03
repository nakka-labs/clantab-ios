import SwiftUI
import ClanTabKit

/// The "This is me" branch (`ACCOUNTS_DESIGN.md` §6): list the group's
/// placeholder members, let the signed-in user pick which one is them, confirm,
/// and link it to their Apple ID. The `memberId` never travels in a link, so a
/// forwarded invite can't auto-claim anyone.
struct ClaimMemberView: View {
    let groupId: String
    let client: ClanTabClient
    let auth: AuthViewModel
    let onClaimed: (_ groupId: String) -> Void
    let onJoinAsGuest: () -> Void
    let onCancel: () -> Void

    @State private var members: [Member]?
    @State private var loadError: String?
    @State private var pendingConfirmation: Member?

    var body: some View {
        Form {
            if let members {
                if members.isEmpty {
                    Section {
                        Text("Everyone in this group is already linked to an account.")
                            .foregroundStyle(.secondary)
                        Button("Join as a guest instead", action: onJoinAsGuest)
                    }
                } else {
                    Section("Which member are you?") {
                        ForEach(members) { member in
                            Button(member.displayName) { pendingConfirmation = member }
                                .disabled(auth.isBusy)
                        }
                    }
                    Section {
                        Button("None of these — join as a guest", action: onJoinAsGuest)
                    }
                }
            } else if loadError == nil {
                Section {
                    HStack { ProgressView(); Text("Loading members…").foregroundStyle(.secondary) }
                }
            }

            if let message = auth.errorMessage ?? loadError {
                Section {
                    Text(message).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("This is me")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back", action: onCancel)
            }
        }
        .task { await loadMembers() }
        .confirmationDialog(
            pendingConfirmation.map { "Link \($0.displayName) to your Apple ID?" } ?? "",
            isPresented: Binding(
                get: { pendingConfirmation != nil },
                set: { if !$0 { pendingConfirmation = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingConfirmation
        ) { member in
            Button("Link \(member.displayName)") {
                Task { await claim(member) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { member in
            Text("\(member.displayName)'s expenses and balance become visible on all your devices.")
        }
    }

    private func loadMembers() async {
        guard members == nil, let token = auth.session?.token else { return }
        do {
            members = try await client.claimableMembers(groupId: groupId, token: token).members
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }

    private func claim(_ member: Member) async {
        if await auth.claim(groupId: groupId, memberId: member.id) {
            onClaimed(groupId)
        }
    }
}
