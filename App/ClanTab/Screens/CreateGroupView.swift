import SwiftUI
import ClanTabKit

struct CreateGroupView: View {
    let client: ClanTabClient
    let identityStore: IdentityStoring
    let onCreated: (String) -> Void
    let onCancel: () -> Void

    /// `CreateGroupResponse` is the *only* place the 6-character join code is
    /// ever available — `GET /api/groups/:groupId` (`DESIGN.md` §2) doesn't
    /// return it, so unlike the capability link, it can't be re-shared later
    /// from Group Home. This stage exists specifically to surface it before
    /// that one chance is gone.
    private enum Stage {
        case form
        case created(CreateGroupResponse)

        var isForm: Bool {
            if case .form = self { return true }
            return false
        }
    }

    @State private var stage: Stage = .form
    @State private var groupName = ""
    @State private var currency = "INR"
    @State private var displayName = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let currencies = AppConfig.supportedCurrencies

    var body: some View {
        Group {
            switch stage {
            case .form:
                form
            case .created(let response):
                createdConfirmation(response)
            }
        }
        .navigationTitle(stage.isForm ? "New Group" : "Share Your Group")
        .toolbar {
            if stage.isForm {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .dismissibleKeyboard()
    }

    private var form: some View {
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
    }

    private func createdConfirmation(_ response: CreateGroupResponse) -> some View {
        let shareURL = AppConfig.groupShareURL(groupId: response.groupId)
        return Form {
            Section("Join Code") {
                Text(response.joinCode)
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                ShareLink("Share Code", item: response.joinCode)
            }
            Section("Or Share the Link") {
                ShareLink("Share Invite Link", item: shareURL)
            }
            Section {
                Button("Continue") {
                    onCreated(response.groupId)
                }
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
            stage = .created(response)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
