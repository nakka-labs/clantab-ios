import SwiftUI
import PhotosUI
import ClanTabKit

/// Join code + invite link, and the cover image — pulled out of
/// `GroupSettingsView`'s own `Form` into their own screen (`CHECKLIST.md`
/// R3: that Form covered too many concerns in one place). Reached the same
/// way `SettingsView` reaches `MySpendingView` — a plain `NavigationLink`
/// inside a `Section`, since `GroupSettingsView` is already hosted in its
/// own `NavigationStack` by `GroupHomeView`'s `.sheet`.
///
/// **Scope note vs. the original R3 ticket text**: that ticket assumed an
/// "Export" row lived in this Form too — it doesn't; CSV/JSON/PDF export
/// lives only in `GroupHomeView`'s own "…" menu. So this pulls out Join
/// Code + Cover Image instead (the two sections that were actually here),
/// which still cuts the top-level Form from ~9 sections to ~7.
struct GroupInfoView: View {
    let groupId: String
    let joinCode: String
    /// `state.group.coverKey` — re-read on every re-render the same way
    /// `GroupSettingsView`'s own `state` does, so a change here (upload,
    /// remove) is visible the moment the parent's `onChanged` refetch lands.
    let coverKey: String?
    let client: ClanTabClient
    let accessToken: String?
    /// Needed by the media-presign endpoint for the cover-image upload
    /// (`CHECKLIST.md` "Group cover image").
    let sessionToken: String?
    let onChanged: () -> Void

    @State private var pickedCover: PhotosPickerItem?
    @State private var isSavingCover = false
    @State private var errorMessage: String?
    @Environment(\.avatarImageLoader) private var avatarLoader

    private var coverImageKey: String { "groups/\(groupId)/cover" }

    var body: some View {
        Form {
            joinCodeSection
            coverImageSection
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Group Info")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickedCover) { _, item in
            guard let item else { return }
            Task { await handlePickedCover(item) }
        }
    }

    private var joinCodeSection: some View {
        Section {
            HStack {
                Text(joinCode)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button {
                    UIPasteboard.general.string = joinCode
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Copy Join Code")
            }
            ShareLink("Share Invite Link", item: AppConfig.groupShareURL(groupId: groupId, accessToken: accessToken))
        } header: {
            Text("Join Code")
        } footer: {
            Text("Anyone with this code can join the group from \"Join with a Code.\"")
        }
    }

    @ViewBuilder
    private var coverImageSection: some View {
        Section {
            HStack(spacing: 12) {
                Group {
                    if coverKey != nil {
                        GroupCoverImage(groupId: groupId, coverKey: coverImageKey, accessToken: accessToken)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Surface.well)
                            .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
                    }
                }
                .frame(width: 72, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                PhotosPicker(
                    selection: $pickedCover,
                    matching: .images,
                    preferredItemEncoding: .compatible,
                    photoLibrary: .shared()
                ) {
                    Text(coverKey == nil ? "Add Cover Image" : "Change Cover")
                }
                .disabled(isSavingCover)

                Spacer()
                if isSavingCover { ProgressView() }
            }

            if coverKey != nil {
                Button("Remove Cover", role: .destructive) {
                    Task { await removeCover() }
                }
                .disabled(isSavingCover)
            }
        } header: {
            Text("Cover Image")
        } footer: {
            Text("Shown on the group's card and at the top of the group. Any member can change it.")
        }
    }

    private func handlePickedCover(_ item: PhotosPickerItem) async {
        errorMessage = nil
        defer { pickedCover = nil }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let picked = UIImage(data: data),
            let jpeg = CoverImage.jpegData(from: picked),
            let compressed = UIImage(data: jpeg)
        else {
            errorMessage = "Couldn't read that photo. Try another."
            return
        }

        isSavingCover = true
        defer { isSavingCover = false }
        do {
            guard let sessionToken else {
                errorMessage = "Sign in to set a cover image."
                return
            }
            let ticket = try await client.presignMediaUpload(
                .groupCover, contentType: "image/jpeg", contentLength: jpeg.count,
                groupId: groupId, token: sessionToken, accessToken: accessToken
            )
            try await client.uploadImage(jpeg, using: ticket)
            _ = try await client.updateGroup(groupId: groupId, coverImage: .commit, accessToken: accessToken)
            avatarLoader?.prime(coverImageKey, with: compressed) // show it instantly everywhere
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }

    private func removeCover() async {
        errorMessage = nil
        isSavingCover = true
        defer { isSavingCover = false }
        do {
            _ = try await client.updateGroup(groupId: groupId, coverImage: .remove, accessToken: accessToken)
            avatarLoader?.invalidate(coverImageKey)
            onChanged()
        } catch {
            errorMessage = friendlyMessage(for: error)
        }
    }
}
