import SwiftUI

/// The one-time "sign in to keep your groups" card on Group Home
/// (`ACCOUNTS_DESIGN.md` §10). Shown once, to a guest, at their 2nd group or 7
/// days of use — dismissable, and never shown again after that.
struct SyncNudgeCard: View {
    var onCredential: (_ identityToken: String, _ userID: String) -> Void
    var onFailure: (_ message: String) -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Keep your groups", systemImage: "icloud")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }

            Text("Sign in with Apple so you don't lose your groups if you switch phones.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            AppleSignInButton(onCredential: onCredential, onFailure: onFailure)
                .frame(height: 40)
        }
        .padding(.vertical, 4)
    }
}
