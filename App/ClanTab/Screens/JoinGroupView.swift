import SwiftUI
import ClanTabKit

/// Two-step form: resolve a 6-character code to a `groupId` (skipped when
/// arriving with a `groupId` already known, e.g. from a deep link), then pick a
/// display name and join.
struct JoinGroupView: View {
    let groupId: String?
    let client: ClanTabClient
    let identityStore: IdentityStoring
    let onJoined: (String) -> Void
    let onCancel: () -> Void

    @State private var joinCode = ""
    @State private var resolvedGroupId: String?
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var effectiveGroupId: String? { groupId ?? resolvedGroupId }

    var body: some View {
        Form {
            if effectiveGroupId == nil {
                Section("Group Code") {
                    TextField("6-character code", text: $joinCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                }
                Section {
                    Button("Find Group") {
                        Task { await resolveCode() }
                    }
                    .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            } else {
                Section("You") {
                    TextField("Your display name", text: $displayName)
                }
                Section {
                    Button {
                        Task { await join() }
                    } label: {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text("Join Group")
                        }
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Join a Group")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private func resolveCode() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await client.resolveJoinCode(joinCode.uppercased())
            resolvedGroupId = response.groupId
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func join() async {
        guard let groupId = effectiveGroupId else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: displayName))
            identityStore.setIdentity(
                GroupIdentity(memberId: response.member.id, displayName: response.member.displayName),
                forGroup: groupId
            )
            onJoined(groupId)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
