import SwiftUI

/// Account settings, reachable from the start screen and Group Home. The
/// permanent home for "sign in to sync" (guests) and — Apple Guideline
/// 5.1.1(v) — "Delete Account" (signed-in users). `ACCOUNTS_DESIGN.md` §10/§11.
struct SettingsView: View {
    let auth: AuthViewModel
    let onDone: () -> Void

    @State private var confirmingDelete = false
    @State private var sheetError: String?

    private let deletionCaveat =
        "Your groups and expenses stay. You'll lose cross-device sync and can't recover this account."

    var body: some View {
        Form {
            Section("Account") {
                if auth.isSignedIn {
                    Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.secondary)
                    Button("Sign Out") { auth.signOut() }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Sync your groups across devices")
                            .font(.subheadline.weight(.medium))
                        Text("Sign in with Apple so you don't lose your groups if you switch phones.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        AppleSignInButton(
                            onCredential: { token, userID in
                                sheetError = nil
                                Task { await auth.signIn(identityToken: token, userID: userID) }
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
            }

            if auth.isSignedIn {
                Section {
                    Button("Delete Account", role: .destructive) {
                        confirmingDelete = true
                    }
                    .disabled(auth.isBusy)
                } footer: {
                    Text(deletionCaveat)
                }
            }

            Section {
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
