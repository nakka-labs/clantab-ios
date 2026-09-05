import SwiftUI
import ClanTabKit

/// "Join with a Code": resolve a 6-character code to a `groupId`, then hand
/// off to `ClaimMemberView` (`MANDATORY_LOGIN_PLAN.md` Part 3) — every
/// signed-in user either claims an existing placeholder or adds themselves
/// fresh there; this screen's only job is the code lookup.
struct JoinGroupView: View {
    let client: ClanTabClient
    /// `accessToken` is the group's *current* capability-link credential
    /// (`ACCESS_TOKEN_PLAN.md` Part 3) — a resolved code always returns the
    /// live one, evergreen across a link rotation.
    let onResolved: (_ groupId: String, _ accessToken: String?) -> Void
    let onCancel: () -> Void

    @State private var joinCode = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Group Code") {
                TextField("6-character code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
            Section {
                Button {
                    Task { await resolveCode() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Find Group")
                    }
                }
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
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
        .dismissibleKeyboard()
    }

    private func resolveCode() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let response = try await client.resolveJoinCode(joinCode.uppercased())
            onResolved(response.groupId, response.accessToken)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
