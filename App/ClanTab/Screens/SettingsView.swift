import SwiftUI
import PhotosUI
import ClanTabKit

/// Account settings — a top-level tab (`CHECKLIST.md` UX audit [6]; used to be
/// a sheet reached from the start screen and Group Home's toolbar gear).
/// Sign in is mandatory (`MANDATORY_LOGIN_PLAN.md` Part 3) — this screen
/// still shows a sign-in prompt for the brief window between "signed out"
/// and "signed back in," plus — Apple Guideline 5.1.1(v) — "Delete Account"
/// once signed in. `ACCOUNTS_DESIGN.md` §10/§11.
struct SettingsView: View {
    let auth: AuthViewModel
    let knownGroups: KnownGroupsStoring
    /// "Show tips again" (`CHECKLIST.md`) resets both of these.
    let onboarding: OnboardingStoring
    let coachMarks: CoachMarkStoring?
    /// Fires once, right after "Delete Account" actually succeeds — there's
    /// no sheet to dismiss anymore now that this is a tab, so `RootView`
    /// just uses it to switch back to the Home tab (which reacts to
    /// `auth.isSignedIn` on its own).
    let onDone: () -> Void

    @Environment(\.avatarImageLoader) private var avatarLoader
    @State private var confirmingDelete = false
    @State private var tipsResetConfirmation = false
    @State private var sheetError: String?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photoError: String?
    @AppStorage("clantab.theme") private var theme = AppTheme.system
    /// Which screen a returning user lands on (`CHECKLIST.md` "Settings:
    /// launch-screen preference"). `""` — the dashboard; a groupId — that
    /// group. Read on launch by `RootView.launchRoute`.
    @AppStorage("clantab.launchGroupId") private var launchGroupId = ""

    private let deletionCaveat =
        "Your groups and expenses stay. You'll lose cross-device sync and can't recover this account."

    var body: some View {
        Form {
            Section {
                if auth.isSignedIn {
                    Label(
                        auth.session?.provider == .google ? "Signed in with Google" : "Signed in with Apple",
                        systemImage: "checkmark.seal.fill"
                    )
                    .foregroundStyle(.secondary)

                    profilePhotoRow

                    Button("Sign Out") { auth.signOut() }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync your groups across devices")
                            .font(.subheadline.weight(.medium))
                        Text("Sign in so you don't lose your groups if you switch phones.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AppleSignInButton(
                            onCredential: { token, userID, authCode in
                                sheetError = nil
                                Task { await auth.signIn(identityToken: token, userID: userID, authorizationCode: authCode) }
                            },
                            onFailure: { sheetError = $0 }
                        )
                        .frame(height: 40)
                        GoogleSignInButton(
                            onCredential: { token in
                                sheetError = nil
                                Task { await auth.signInWithGoogle(identityToken: token) }
                            },
                            onFailure: { sheetError = $0 }
                        )
                        .frame(height: 40)
                    }
                    .padding(.vertical, 4)
                }

                if let message = auth.errorMessage ?? sheetError ?? photoError {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Account")
            }

            // "Settle Across Groups" used to live here as its own screen
            // (`PeopleView`) — retired (`CHECKLIST.md` UX audit [8]): the
            // same capability now lives on every friend's own detail screen,
            // reached from the Friends tab, so there's no separate entry
            // point to keep. Delete Account used to be red text one row
            // below Sign Out, with no separating header — the least emphasis
            // of any destructive action in the app, despite being the most
            // irreversible one. Now it gets the same "Danger Zone" treatment
            // as Group Settings' Regenerate/Archive/Leave trio (`CHECKLIST.md`
            // UX audit fresh-eyes-pass [3]).
            if auth.isSignedIn {
                Section {
                    DangerZoneRow(
                        icon: "person.crop.circle.badge.xmark",
                        title: "Delete Account",
                        caption: deletionCaveat,
                        isLoading: auth.isBusy,
                        action: { confirmingDelete = true }
                    )
                } header: {
                    Text("Danger Zone").foregroundStyle(.red)
                }
            }

            Section("App") {
                Picker("Appearance", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                if auth.isSignedIn, !launchGroups.isEmpty {
                    Picker("Open at Launch", selection: $launchGroupId) {
                        Text("Dashboard").tag("")
                        ForEach(launchGroups) { group in
                            Text(Self.launchLabel(for: group)).tag(group.groupId)
                        }
                    }
                }
                LabeledContent("Version", value: Self.appVersion)

                Button("Show Tips Again") {
                    onboarding.reset()
                    coachMarks?.resetAll()
                    tipsResetConfirmation = true
                }
            }
        }
        .alert("Tips Reset", isPresented: $tipsResetConfirmation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The walkthrough and every one-time tip will show again.")
        }
        .navigationTitle("Settings")
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            Task { await handlePickedPhoto(item) }
        }
        .confirmationDialog(
            "Delete your account?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { if await auth.deleteAccount() { onDone() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionCaveat)
        }
    }

    // MARK: - Profile photo (CHECKLIST.md "Profile photos")

    @ViewBuilder
    private var profilePhotoRow: some View {
        HStack(spacing: 12) {
            MemberAvatar(name: myDisplayName, avatarKey: auth.myAvatarKey, size: 44)

            PhotosPicker(
                selection: $pickedPhoto,
                matching: .images,
                preferredItemEncoding: .compatible,
                photoLibrary: .shared()
            ) {
                Text(auth.myAvatarKey == nil ? "Add Profile Photo" : "Change Photo")
            }
            .disabled(auth.isUpdatingAvatar)

            Spacer()

            if auth.isUpdatingAvatar {
                ProgressView()
            }
        }

        if auth.myAvatarKey != nil {
            Button("Remove Photo", role: .destructive) {
                Task {
                    if let key = await auth.removeAvatar() {
                        avatarLoader?.invalidate(key)
                    }
                }
            }
            .disabled(auth.isUpdatingAvatar)
        }
    }

    /// The signed-in user's name for the initials fallback — their name in the
    /// most-recently-claimed group, or a neutral placeholder.
    private var myDisplayName: String {
        auth.groups.first?.displayName ?? "You"
    }

    private func handlePickedPhoto(_ item: PhotosPickerItem) async {
        photoError = nil
        defer { pickedPhoto = nil }

        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let picked = UIImage(data: data),
            let jpeg = ProfileImage.jpegData(from: picked),
            let compressed = UIImage(data: jpeg)
        else {
            photoError = "Couldn't read that photo. Try another."
            return
        }

        if let key = await auth.setAvatar(jpegData: jpeg) {
            // Show the new photo immediately, everywhere, without a round-trip.
            avatarLoader?.prime(key, with: compressed)
        }
        // A failure leaves `auth.errorMessage` set (shown above).
    }

    /// The known-groups list for the "Open at Launch" picker — same source and
    /// order (most-recently-opened first) as the start screen's list.
    private var launchGroups: [KnownGroup] { knownGroups.all() }

    /// A group's row label in the launch picker: its emoji (if any) + name,
    /// matching `GroupsListView`'s `"Group"` fallback for an unnamed group.
    static func launchLabel(for group: KnownGroup) -> String {
        let name = group.name.isEmpty ? "Group" : group.name
        if let emoji = group.emoji, !emoji.isEmpty { return "\(emoji) \(name)" }
        return name
    }

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
