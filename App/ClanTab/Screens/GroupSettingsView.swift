import SwiftUI
import ClanTabKit

/// Rename the group, change its default currency, rename or remove members, or
/// leave the group on this device (`DESIGN.md` §2). Reached from Group Home's
/// "Group Options" menu.
struct GroupSettingsView: View {
    let groupId: String
    /// A live snapshot from `GroupViewModel` — the member list re-renders after
    /// `onChanged` triggers a refetch.
    let state: GroupStateResponse
    let client: ClanTabClient
    /// This group's capability-link credential (`ACCESS_TOKEN_PLAN.md`) — used
    /// to authorize "Regenerate Link" itself, same as any other group route.
    let accessToken: String?
    let onChanged: () -> Void
    /// Called with the fresh token right after a successful regenerate, so
    /// the caller (`GroupHomeView`'s `GroupViewModel`) can start using it
    /// immediately — before its own next `refetch()` would otherwise notice.
    let onRegenerated: (String) -> Void
    let onLeave: () -> Void
    let onDone: () -> Void

    @State private var name: String
    @State private var currency: String
    @State private var renamingMember: Member?
    @State private var renameText = ""
    @State private var newMemberName = ""
    @State private var isAddingMember = false
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var confirmingLeave = false
    @State private var confirmingRegenerate = false
    @State private var isRegenerating = false

    init(
        groupId: String,
        state: GroupStateResponse,
        client: ClanTabClient,
        accessToken: String? = nil,
        onChanged: @escaping () -> Void,
        onRegenerated: @escaping (String) -> Void = { _ in },
        onLeave: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.groupId = groupId
        self.state = state
        self.client = client
        self.accessToken = accessToken
        self.onChanged = onChanged
        self.onRegenerated = onRegenerated
        self.onLeave = onLeave
        self.onDone = onDone
        _name = State(initialValue: state.group.name)
        _currency = State(initialValue: state.group.currency)
    }

    private var currencyChoices: [String] {
        AppConfig.supportedCurrencies.contains(currency)
            ? AppConfig.supportedCurrencies
            : [currency] + AppConfig.supportedCurrencies
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var isDirty: Bool { trimmedName != state.group.name || currency != state.group.currency }
    private var trimmedNewMemberName: String { newMemberName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Group name", text: $name)
                Picker("Default currency", selection: $currency) {
                    ForEach(currencyChoices, id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Group")
            } footer: {
                Text("The default currency for new expenses. Existing expenses keep the currency they were entered in.")
            }

            Section {
                ForEach(state.members) { member in
                    Button {
                        renameText = member.displayName
                        renamingMember = member
                    } label: {
                        HStack {
                            Text(member.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "pencil").font(.caption).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { Task { await remove(member) } }
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                Text("A member can only be removed if they have no expenses or settlements and aren't signed in.")
            }

            Section {
                HStack {
                    TextField("Name", text: $newMemberName)
                        .submitLabel(.done)
                        .onSubmit { Task { await addMember() } }
                    Button("Add") { Task { await addMember() } }
                        .disabled(isAddingMember || trimmedNewMemberName.isEmpty)
                }
            } header: {
                Text("Add Someone")
            } footer: {
                Text("Adds them to the ledger by name alone — no app or account needed. They can sign in and claim this spot for themselves later.")
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    confirmingRegenerate = true
                } label: {
                    if isRegenerating {
                        ProgressView()
                    } else {
                        Text("Regenerate Link")
                    }
                }
                .disabled(isRegenerating)
            } footer: {
                Text("Makes a fresh invite link and code; the old ones stop working immediately, for anyone still holding them. Not undoable.")
            }

            Section {
                Button("Leave This Group", role: .destructive) { confirmingLeave = true }
            } footer: {
                Text("Removes this group from this device. Your expenses stay for everyone else.")
            }
        }
        .navigationTitle("Group Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
                    .disabled(isBusy || !isDirty || trimmedName.isEmpty)
            }
        }
        .dismissibleKeyboard()
        .alert(
            "Rename Member",
            isPresented: Binding(get: { renamingMember != nil }, set: { if !$0 { renamingMember = nil } }),
            presenting: renamingMember
        ) { member in
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await rename(member) } }
        }
        .confirmationDialog("Leave this group?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave", role: .destructive, action: onLeave)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It'll be removed from this device. Your expenses stay for everyone else.")
        }
        .confirmationDialog("Regenerate the invite link?", isPresented: $confirmingRegenerate, titleVisibility: .visible) {
            Button("Regenerate", role: .destructive) { Task { await regenerateLink() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The old link and join code stop working immediately, for anyone still holding them. Not undoable.")
        }
    }

    private func save() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await client.updateGroup(
                groupId: groupId,
                name: trimmedName != state.group.name ? trimmedName : nil,
                currency: currency != state.group.currency ? currency : nil,
                accessToken: accessToken
            )
            onChanged()
            onDone()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func rename(_ member: Member) async {
        let newName = renameText.trimmingCharacters(in: .whitespaces)
        renamingMember = nil
        guard !newName.isEmpty, newName != member.displayName else { return }
        errorMessage = nil
        do {
            _ = try await client.renameMember(groupId: groupId, memberId: member.id, displayName: newName, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Add a placeholder member by name alone (`MANDATORY_LOGIN_PLAN.md`
    /// Part 2.5) — the same `POST .../members` endpoint the join-by-link flow
    /// already uses, just triggered by an existing member instead of the
    /// person themselves. No identity attached; they can claim this spot
    /// later via the existing claim flow (`ACCOUNTS_DESIGN.md` §6).
    private func addMember() async {
        let trimmed = trimmedNewMemberName
        guard !trimmed.isEmpty else { return }
        errorMessage = nil
        isAddingMember = true
        defer { isAddingMember = false }
        do {
            _ = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: trimmed), accessToken: accessToken)
            newMemberName = ""
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func remove(_ member: Member) async {
        errorMessage = nil
        do {
            try await client.removeMember(groupId: groupId, memberId: member.id, accessToken: accessToken)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    /// Rotate the group's access token (`ACCESS_TOKEN_PLAN.md` Part 1) —
    /// every previously shared link/code stops working immediately.
    private func regenerateLink() async {
        errorMessage = nil
        isRegenerating = true
        defer { isRegenerating = false }
        do {
            let response = try await client.regenerateLink(groupId: groupId, accessToken: accessToken)
            onRegenerated(response.accessToken)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
