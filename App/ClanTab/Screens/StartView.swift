import ClanTabKit
import SwiftUI

/// The very first screen for a device with no active group: open one of the
/// groups this identity knows, create a new group, or join by code. Sign-in
/// (Apple or Google) is mandatory before any of that — no guest tier
/// (`MANDATORY_LOGIN_PLAN.md` Part 3).
struct StartView: View {
    let onCreate: () -> Void
    let onJoinWithCode: () -> Void
    var groups: [KnownGroup] = []
    var onOpenGroup: (_ groupId: String) -> Void = { _ in }
    var onRemoveGroup: (_ groupId: String) -> Void = { _ in }
    var isSignedIn: Bool = false
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

            if isSignedIn {
                if !groups.isEmpty {
                    GroupsListView(groups: groups, onOpenGroup: onOpenGroup, onRemoveGroup: onRemoveGroup)
                }
                Spacer()
                VStack(spacing: 12) {
                    Button("Create a Group", action: onCreate)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    Button("Join with a Code", action: onJoinWithCode)
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                }
                .frame(maxWidth: .infinity)
            } else {
                Spacer()
                signInSection
            }
        }
        .padding()
        .toolbar {
            if isSignedIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onOpenSettings) {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
            }
        }
    }

    private var signInSection: some View {
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

            Text("Sign in to create or join a group.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let message = authError ?? sheetError {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
