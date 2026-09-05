import SwiftUI
import ClanTabKit

/// Shown when a signed-in user has no membership yet in a group — arriving via
/// an invite link or a resolved join code (`ACCOUNTS_DESIGN.md` §6). Pick which
/// existing placeholder member is you, or add yourself as a new member.
/// Collapses the old two-screen chooser + guest-join branch into one
/// (`MANDATORY_LOGIN_PLAN.md` Part 3): both outcomes always claim with an
/// identity now — there's no more "join as guest". The `memberId` never
/// travels in a link, so a forwarded invite can't auto-claim anyone.
struct ClaimMemberView: View {
    let groupId: String
    let client: ClanTabClient
    /// This group's capability-link credential (`ACCESS_TOKEN_PLAN.md`), from
    /// wherever this screen was reached — the link, or a resolved join code.
    let accessToken: String?
    let auth: AuthViewModel
    let onClaimed: (_ groupId: String) -> Void
    let onCancel: () -> Void

    @State private var members: [Member]?
    @State private var loadError: String?
    @State private var pendingConfirmation: Member?
    @State private var newMemberName = ""
    @State private var isJoiningFresh = false

    private var trimmedNewMemberName: String { newMemberName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            if let members {
                if !members.isEmpty {
                    Section("Which member are you?") {
                        ForEach(members) { member in
                            Button(member.displayName) { pendingConfirmation = member }
                                .disabled(auth.isBusy)
                        }
                    }
                }
                Section(members.isEmpty ? "Add Yourself" : "Not Listed?") {
                    TextField("Your display name", text: $newMemberName)
                    Button {
                        Task { await joinFresh() }
                    } label: {
                        if isJoiningFresh {
                            ProgressView()
                        } else {
                            Text("Join as a New Member")
                        }
                    }
                    .disabled(trimmedNewMemberName.isEmpty || auth.isBusy || isJoiningFresh)
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
        .navigationTitle("Join This Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .dismissibleKeyboard()
        .task { await loadMembers() }
        .confirmationDialog(
            pendingConfirmation.map { "Link \($0.displayName) to your account?" } ?? "",
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
            members = try await client.claimableMembers(groupId: groupId, token: token, accessToken: accessToken).members
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }

    private func claim(_ member: Member) async {
        if await auth.claim(groupId: groupId, memberId: member.id, accessToken: accessToken) {
            onClaimed(groupId)
        }
    }

    /// Add a brand-new member (your own display name) and immediately claim
    /// it — the "join fresh" outcome, now always identity-linked.
    private func joinFresh() async {
        let name = trimmedNewMemberName
        guard !name.isEmpty else { return }
        loadError = nil
        isJoiningFresh = true
        defer { isJoiningFresh = false }
        do {
            let response = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: name), accessToken: accessToken)
            if await auth.claim(groupId: groupId, memberId: response.member.id, accessToken: accessToken) {
                onClaimed(groupId)
            }
        } catch {
            loadError = friendlyMessage(for: error)
        }
    }
}
