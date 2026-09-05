import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

/// The Google Sign-In button, hand-rolled via `ASWebAuthenticationSession` and
/// the OAuth 2.0 Authorization Code + PKCE flow — not the official Google
/// Sign-In SDK, to keep the zero-third-party-dependency rule (`AGENTS.md`,
/// `DESIGN.md` §7). PKCE (not the legacy implicit `id_token` flow) matches
/// Google's current documented native-app guidance and needs no client
/// secret, which iOS OAuth clients don't have. Mirrors `AppleSignInButton`'s
/// shape and error handling.
struct GoogleSignInButton: View {
    var onCredential: (_ identityToken: String) -> Void
    var onFailure: (_ message: String) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @State private var activeSession: ASWebAuthenticationSession?
    private let presentationCoordinator = PresentationContextCoordinator()

    private static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    private static let tokenEndpoint = "https://oauth2.googleapis.com/token"
    /// Matches the `CFBundleURLTypes` entry in `App/project.yml` — Google's
    /// reversed-client-id scheme, the standard redirect mechanism for the
    /// "iOS" OAuth client type (`MANDATORY_LOGIN_PLAN.md` Part 1). The path
    /// after the colon is arbitrary — Google's iOS client type validates the
    /// scheme, not a registered exact redirect URI.
    private static let redirectURI = "\(AppConfig.googleReversedClientID):/oauth2redirect"

    var body: some View {
        Button(action: startSignIn) {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("Sign in with Google")
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
        }
        .buttonStyle(.bordered)
        .tint(colorScheme == .dark ? .white : .black)
    }

    private func startSignIn() {
        let verifier = Self.randomCodeVerifier()
        guard let url = Self.authorizationURL(codeChallenge: Self.codeChallenge(for: verifier)) else {
            onFailure("Couldn't start Google sign-in.")
            return
        }
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: AppConfig.googleReversedClientID
        ) { callbackURL, error in
            handle(callbackURL: callbackURL, error: error, codeVerifier: verifier)
        }
        session.presentationContextProvider = presentationCoordinator
        activeSession = session
        session.start()
    }

    private func handle(callbackURL: URL?, error: Error?, codeVerifier: String) {
        if let error {
            activeSession = nil
            if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { return }
            onFailure("Sign in didn't complete. Please try again.")
            return
        }
        guard
            let callbackURL,
            let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else {
            activeSession = nil
            onFailure("Google didn't return a usable sign-in. Please try again.")
            return
        }
        Task {
            do {
                let identityToken = try await Self.exchangeCode(code, codeVerifier: codeVerifier)
                activeSession = nil
                onCredential(identityToken)
            } catch {
                activeSession = nil
                onFailure("Google sign-in couldn't be completed. Please try again.")
            }
        }
    }

    private static func authorizationURL(codeChallenge: String) -> URL? {
        var components = URLComponents(string: authorizationEndpoint)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
        return components?.url
    }

    /// Trade the authorization `code` for tokens at Google's token endpoint —
    /// straight from the device, no client secret (PKCE covers a public
    /// client's security instead). Returns the `id_token`, the only thing the
    /// worker needs (`POST /api/auth/google`).
    private static func exchangeCode(_ code: String, codeVerifier: String) async throws -> String {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = [
            URLQueryItem(name: "client_id", value: AppConfig.googleClientID),
            URLQueryItem(name: "code", value: code),
            URLQueryItem(name: "code_verifier", value: codeVerifier),
            URLQueryItem(name: "grant_type", value: "authorization_code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
        ]
        request.httpBody = body.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let idToken = json["id_token"] as? String
        else {
            throw GoogleSignInError.tokenExchangeFailed
        }
        return idToken
    }

    private static func randomCodeVerifier(length: Int = 64) -> String {
        let charset: [Character] = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private enum GoogleSignInError: Error {
    case tokenExchangeFailed
}

/// `ASWebAuthenticationSession` needs a window to present from. A tiny
/// `NSObject` conformance — SwiftUI views can't conform to
/// `ASWebAuthenticationPresentationContextProviding` themselves.
private final class PresentationContextCoordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
