import AuthenticationServices
import Foundation

/// Turns an Apple/Google sign-in failure into copy that distinguishes the
/// common causes — mirrors `friendlyMessage(for:)`'s job for the rest of the
/// app, scoped to what `AppleSignInButton`/`GoogleSignInButton` can throw.
/// Pure so it's unit-testable without driving the actual auth UI.
/// `nil` means "silent" — the user cancelled, say nothing.
enum SignInErrorMessage {
    static let noAppleID = "No Apple ID is signed in on this device. Add one in Settings, then try again."
    static let noNetwork = "No internet connection. Check your connection and try again."
    static let genericFailure = "Sign in didn't complete. Please try again."

    static func forApple(_ error: Error) -> String? {
        if let authError = error as? ASAuthorizationError {
            if authError.code == .canceled { return nil }
            // Apple reports "no Apple ID configured on this device" as
            // `.unknown` (1000) rather than a dedicated case — there isn't a
            // more specific one to switch on.
            if authError.code == .unknown && !isOffline(error) { return noAppleID }
        }
        if isOffline(error) { return noNetwork }
        return genericFailure
    }

    static func forGoogle(_ error: Error) -> String? {
        if let webAuthError = error as? ASWebAuthenticationSessionError, webAuthError.code == .canceledLogin {
            return nil
        }
        if isOffline(error) { return noNetwork }
        return genericFailure
    }

    /// Walks `NSUnderlyingErrorKey` a few levels down — Apple's own frameworks
    /// often wrap a plain `URLError` inside their own error domain.
    private static func isOffline(_ error: Error) -> Bool {
        var current: Error? = error
        var depth = 0
        while let err = current, depth < 5 {
            let nsError = err as NSError
            if nsError.domain == NSURLErrorDomain { return true }
            current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
            depth += 1
        }
        return false
    }
}
