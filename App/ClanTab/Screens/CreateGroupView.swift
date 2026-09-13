import SwiftUI
import PhotosUI
import ClanTabKit

struct CreateGroupView: View {
    let client: ClanTabClient
    let auth: AuthViewModel
    /// `accessToken` is the new group's capability-link credential
    /// (`ACCESS_TOKEN_PLAN.md`) — `nil` only if creation somehow raced a
    /// worker that predates the feature entirely.
    let onCreated: (_ groupId: String, _ accessToken: String?) -> Void
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

    // Cover photo + emoji, offered right on the "created" confirmation
    // stage (round-3 playtest, 2026-09-13 — both already existed post-
    // creation via Group Settings, just never surfaced during creation
    // itself). Mirrors `GroupSettingsView`'s own emoji/cover fields, scaled
    // down: no separate Save step, each pick applies immediately.
    @State private var emoji = ""
    @State private var pickedCover: PhotosPickerItem?
    @State private var isSavingCover = false
    @State private var identityErrorMessage: String?

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
        let shareURL = AppConfig.groupShareURL(groupId: response.groupId, accessToken: response.group.accessToken)
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
            identitySection(response)
            Section {
                Button("Continue") {
                    onCreated(response.groupId, response.group.accessToken)
                }
            }
        }
        .onChange(of: pickedCover) { _, item in
            guard let item else { return }
            Task { await handlePickedCover(item, response) }
        }
    }

    /// Cover photo + emoji, both optional and skippable — "Continue" above
    /// works regardless of whether either was set.
    @ViewBuilder
    private func identitySection(_ response: CreateGroupResponse) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji").foregroundStyle(.primary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        emojiChip(nil, isSelected: emoji.isEmpty, response: response) {
                            Image(systemName: "slash.circle").font(.body)
                        }
                        ForEach(GroupSettingsView.emojiOptions, id: \.self) { option in
                            emojiChip(option, isSelected: emoji == option, response: response) {
                                Text(option).font(.title3)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            HStack(spacing: 12) {
                PhotosPicker(
                    selection: $pickedCover,
                    matching: .images,
                    preferredItemEncoding: .compatible,
                    photoLibrary: .shared()
                ) {
                    Text("Add Cover Image")
                }
                .disabled(isSavingCover)
                Spacer()
                if isSavingCover { ProgressView() }
            }
            if let identityErrorMessage {
                Text(identityErrorMessage).font(.caption).foregroundStyle(.red)
            }
        } header: {
            Text("Make It Yours")
        } footer: {
            Text("Optional — both can be changed anytime from Group Options.")
        }
    }

    private func emojiChip<Label: View>(
        _ value: String?, isSelected: Bool, response: CreateGroupResponse, @ViewBuilder label: () -> Label
    ) -> some View {
        Button {
            let chosen = value ?? ""
            emoji = chosen
            Task { await setEmoji(chosen, response) }
        } label: {
            label()
                .frame(width: 40, height: 40)
                .background(isSelected ? Color.accentColor.opacity(0.22) : Surface.well, in: Circle())
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value.map { "Emoji \($0)" } ?? "No emoji")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func setEmoji(_ value: String, _ response: CreateGroupResponse) async {
        identityErrorMessage = nil
        do {
            _ = try await client.updateGroup(
                groupId: response.groupId,
                emoji: value.isEmpty ? .cleared : .set(value),
                accessToken: response.group.accessToken
            )
        } catch {
            identityErrorMessage = friendlyMessage(for: error)
        }
    }

    private func handlePickedCover(_ item: PhotosPickerItem, _ response: CreateGroupResponse) async {
        identityErrorMessage = nil
        defer { pickedCover = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let picked = UIImage(data: data),
            let jpeg = CoverImage.jpegData(from: picked)
        else {
            identityErrorMessage = "Couldn't read that photo. Try another."
            return
        }
        guard let sessionToken = auth.session?.token else {
            identityErrorMessage = "Sign in to set a cover image."
            return
        }
        isSavingCover = true
        defer { isSavingCover = false }
        do {
            let ticket = try await client.presignMediaUpload(
                .groupCover, contentType: "image/jpeg", contentLength: jpeg.count,
                groupId: response.groupId, token: sessionToken, accessToken: response.group.accessToken
            )
            try await client.uploadImage(jpeg, using: ticket)
            _ = try await client.updateGroup(
                groupId: response.groupId, coverImage: .commit, accessToken: response.group.accessToken
            )
        } catch {
            identityErrorMessage = friendlyMessage(for: error)
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
            // Claim the creator's own membership right away so it shows up in
            // `auth.groups` (`MANDATORY_LOGIN_PLAN.md` Part 3) — best-effort;
            // the group is already created and locally remembered either way,
            // so a transient failure here isn't worth blocking on.
            _ = await auth.claim(groupId: response.groupId, memberId: response.member.id, accessToken: response.group.accessToken)
            stage = .created(response)
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
