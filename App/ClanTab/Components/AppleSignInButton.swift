import AuthenticationServices
import SwiftUI

/// The `SignInWithAppleButton` plus the credential-extraction glue, in one
/// place. Requests no scopes (`ACCOUNTS_DESIGN.md` §5 — the product needs
/// neither email nor name). A user cancelling the sheet is silent; anything
/// else calls `onFailure` with a short message.
struct AppleSignInButton: View {
    var onCredential: (_ identityToken: String, _ userID: String) -> Void
    var onFailure: (_ message: String) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SignInWithAppleButton(
            .signIn,
            onRequest: { $0.requestedScopes = [] },
            onCompletion: handle
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let identityToken = String(data: tokenData, encoding: .utf8)
            else {
                onFailure("Apple didn't return a usable sign-in. Please try again.")
                return
            }
            onCredential(identityToken, credential.user)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            onFailure("Sign in didn't complete. Please try again.")
        }
    }
}
