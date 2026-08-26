import SwiftUI
import SquareKit

struct CreateGroupView: View {
    let client: SquarelyClient
    let identityStore: IdentityStoring
    let onCreated: (String) -> Void
    let onCancel: () -> Void

    @State private var groupName = ""
    @State private var currency = "INR"
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let currencies = ["INR", "USD", "EUR", "GBP", "AUD", "CAD"]

    var body: some View {
        Form {
            Section("Group") {
                TextField("Group name", text: $groupName)
                Picker("Currency", selection: $currency) {
                    ForEach(currencies, id: \.self) { code in
                        Text(code).tag(code)
                    }
                }
            }
            Section("You") {
                TextField("Your display name", text: $displayName)
            }
            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            Section {
                Button {
                    Task { await createGroup() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Create Group")
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .navigationTitle("New Group")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
    }

    private var canSubmit: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func createGroup() async {
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let response = try await client.createGroup(
                CreateGroupRequest(name: groupName, currency: currency, creatorDisplayName: displayName)
            )
            identityStore.setIdentity(
                GroupIdentity(memberId: response.member.id, displayName: response.member.displayName),
                forGroup: response.groupId
            )
            onCreated(response.groupId)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
