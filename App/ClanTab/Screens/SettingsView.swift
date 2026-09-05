import SwiftUI
import ClanTabKit

/// Account settings, reachable from the start screen and Group Home. Sign in
/// is mandatory (`MANDATORY_LOGIN_PLAN.md` Part 3) — this screen still shows a
/// sign-in prompt for the brief window between "signed out" and "signed back
/// in," plus — Apple Guideline 5.1.1(v) — "Delete Account" once signed in.
/// `ACCOUNTS_DESIGN.md` §10/§11.
struct SettingsView: View {
    let auth: AuthViewModel
    let client: ClanTabClient
    let onDone: () -> Void

    @State private var confirmingDelete = false
    @State private var sheetError: String?

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

                if let message = auth.errorMessage ?? sheetError {
                    Text(message).font(.caption).foregroundStyle(.red)
                }

                if auth.isSignedIn {
                    NavigationLink("Settle Across Groups") {
                        PeopleView(auth: auth, client: client)
                    }

                    Button("Delete Account", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(auth.isBusy)
                }
            } header: {
                Text("Account")
            } footer: {
                if auth.isSignedIn {
                    Text(deletionCaveat)
                }
            }

            Section("App") {
                LabeledContent("Version", value: Self.appVersion)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done", action: onDone)
            }
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

    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
