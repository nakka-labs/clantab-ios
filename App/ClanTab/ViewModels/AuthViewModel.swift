import AuthenticationServices
import Foundation
import Observation
import ClanTabKit

/// Where the signed-in Apple credential stands right now, as reported by
/// `ASAuthorizationAppleIDProvider.getCredentialState` on launch
/// (`ACCOUNTS_DESIGN.md` §3). Mapped to a plain enum so the launch-time decision
/// is a pure function, testable without `AuthenticationServices`.
enum CredentialStanding: Equatable, Sendable {
    case authorized
    case revoked
    case notFound
    /// No stored session to check — nothing to do.
    case noSession
}

/// Owns the optional "Sign in with Apple" identity layer. Guests never touch
/// this — the app works exactly as before without a session. A session only
/// unlocks cross-device group sync (`ACCOUNTS_DESIGN.md` §4, §7).
@MainActor
@Observable
final class AuthViewModel {
    /// What `handleLaunch` should do with a restored session.
    enum LaunchDecision: Equatable {
        /// No stored session, or nothing to do.
        case none
        /// Keep using the stored token as-is.
        case keep
        /// Token still valid but near expiry — trade it for a fresh one.
        case refresh
        /// Expired, or the Apple credential was revoked / is gone — drop to guest.
        case discard
    }

    private let client: ClanTabClient
    private let sessionStore: SessionStoring
    /// Injectable so tests don't need a real Apple credential. Returns `.noSession`
    /// when there's nothing stored to check.
    private let credentialStanding: @Sendable (_ appleUserID: String) async -> CredentialStanding

    private(set) var session: StoredSession?
    /// The identity's groups from the last sign-in / refresh. Consumed by the
    /// group-list model (step 6c); just carried here for now.
    private(set) var groups: [GroupMembershipSummary] = []
    private(set) var isBusy = false
    private(set) var errorMessage: String?

    var isSignedIn: Bool { session != nil }

    init(
        client: ClanTabClient,
        sessionStore: SessionStoring,
        credentialStanding: @escaping @Sendable (_ appleUserID: String) async -> CredentialStanding = AuthViewModel.liveCredentialStanding
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.credentialStanding = credentialStanding
        self.session = sessionStore.load()
    }

    // MARK: - Sign in / out

    /// Exchange a verified Apple credential for a session (`ACCOUNTS_DESIGN.md` §5).
    /// `userID` is `ASAuthorizationAppleIDCredential.user` — stored for the
    /// launch-time credential-state check.
    func signIn(identityToken: String, userID: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.signInWithApple(identityToken: identityToken)
            let session = StoredSession(
                token: response.sessionToken,
                appleUserID: userID,
                expiresAt: response.expiresAt
            )
            sessionStore.save(session)
            self.session = session
            self.groups = response.groups ?? []
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    /// Drop the local session — back to guest mode. There is no server-side
    /// revocation (`ACCOUNTS_DESIGN.md` §3); the token simply expires on its own.
    func signOut() {
        sessionStore.clear()
        session = nil
        groups = []
    }

    // MARK: - Launch

    /// On every launch: restore the session, verify the Apple credential is still
    /// good, and refresh the token if it's near expiry.
    func handleLaunch() async {
        session = sessionStore.load()
        guard let current = session else { return }

        let standing = await credentialStanding(current.appleUserID)
        switch Self.launchDecision(session: current, standing: standing, now: Date()) {
        case .none, .keep:
            break
        case .discard:
            signOut()
        case .refresh:
            await refreshSession()
        }
    }

    /// Pure launch-time policy (`ACCOUNTS_DESIGN.md` §3).
    nonisolated static func launchDecision(session: StoredSession?, standing: CredentialStanding, now: Date) -> LaunchDecision {
        guard let session else { return .none }
        if session.isExpired(now: now) { return .discard }
        switch standing {
        case .revoked, .notFound:
            return .discard
        case .noSession, .authorized:
            return session.needsRefresh(now: now) ? .refresh : .keep
        }
    }

    private func refreshSession() async {
        guard let current = session else { return }
        do {
            let response = try await client.refreshSession(token: current.token)
            let updated = StoredSession(
                token: response.sessionToken,
                appleUserID: current.appleUserID,
                expiresAt: response.expiresAt
            )
            sessionStore.save(updated)
            session = updated
        } catch ClanTabClientError.server(let code, _) where code == "INVALID_SESSION" {
            signOut()
        } catch {
            // Transient failure — the current token is still valid, try again next launch.
        }
    }

    // MARK: - Helpers

    nonisolated static func friendlyMessage(for error: Error) -> String {
        switch error as? ClanTabClientError {
        case .server(let code, let message):
            return code == "INVALID_APPLE_TOKEN"
                ? "That Apple sign-in couldn't be verified. Please try again."
                : message
        case .notFound, .invalidResponse, .decodingFailed, .none:
            return "Couldn't reach ClanTab. Check your connection and try again."
        }
    }

    /// The real `getCredentialState` call. Isolated here (and behind the
    /// injectable closure) so the rest of the type stays testable.
    static let liveCredentialStanding: @Sendable (_ appleUserID: String) async -> CredentialStanding = { appleUserID in
        await withCheckedContinuation { continuation in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                switch state {
                case .authorized:
                    continuation.resume(returning: .authorized)
                case .revoked:
                    continuation.resume(returning: .revoked)
                case .notFound:
                    continuation.resume(returning: .notFound)
                case .transferred:
                    // App transferred between developer accounts — treat like a
                    // revoke: force a fresh sign-in.
                    continuation.resume(returning: .revoked)
                @unknown default:
                    // Don't sign someone out over an enum case we don't know.
                    continuation.resume(returning: .authorized)
                }
            }
        }
    }
}
