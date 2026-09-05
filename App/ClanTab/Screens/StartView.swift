import ClanTabKit
import SwiftUI

/// The very first screen for a device with no remembered group: open one of the
/// groups this device already knows, create a new group, or join by code.
/// Optionally sign in with Apple so claimed memberships sync across devices
/// (`ACCOUNTS_DESIGN.md` §4) — entirely optional, guests get the full app.
struct StartView: View {
    let onCreate: () -> Void
    let onJoinWithCode: () -> Void
    var groups: [KnownGroup] = []
    var onOpenGroup: (_ groupId: String) -> Void = { _ in }
    var onRemoveGroup: (_ groupId: String) -> Void = { _ in }
    var isSignedIn: Bool = false
    /// Which provider the current session used, for the signed-in label. `nil`
    /// while signed out.
    var signedInProvider: StoredSession.Provider? = nil
    var isSigningIn: Bool = false
    /// Error from exchanging the credential (network / verification), owned by
    /// `AuthViewModel`. The credential-sheet's own failures are handled locally.
    var authError: String? = nil
    var onSignIn: (_ identityToken: String, _ userID: String, _ authorizationCode: String?) -> Void = { _, _, _ in }
    var onSignInWithGoogle: (_ identityToken: String) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}

    @State private var sheetError: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text("ClanTab")
                    .font(.largeTitle.bold())
                Text("Split expenses with friends. No ads.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if !groups.isEmpty {
                yourGroupsSection
            }

            Spacer()
            VStack(spacing: 12) {
                Button("Create a Group", action: onCreate)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Join with a Code", action: onJoinWithCode)
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                signInSection
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    private var yourGroupsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR GROUPS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(groups) { group in
                Button {
                    onOpenGroup(group.groupId)
                } label: {
                    HStack {
                        Text(group.name.isEmpty ? "Group" : group.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove from This Device", systemImage: "minus.circle", role: .destructive) {
                        onRemoveGroup(group.groupId)
                    }
                }

                if group.id != groups.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var signInSection: some View {
        if isSignedIn {
            Button(action: onOpenSettings) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                    Text(signedInProvider == .google ? "Signed in with Google" : "Signed in with Apple")
                    Image(systemName: "chevron.right").font(.caption2)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        } else {
            VStack(spacing: 8) {
                AppleSignInButton(
                    onCredential: { token, userID, authCode in
                        sheetError = nil
                        onSignIn(token, userID, authCode)
                    },
                    onFailure: { sheetError = $0 }
                )
                .frame(height: 44)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.5 : 1)

                GoogleSignInButton(
                    onCredential: { token in
                        sheetError = nil
                        onSignInWithGoogle(token)
                    },
                    onFailure: { sheetError = $0 }
                )
                .frame(height: 44)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.5 : 1)

                Text("Optional — sync your groups across devices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let message = authError ?? sheetError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.top, 4)
        }
    }
}
