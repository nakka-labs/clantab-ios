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

/// Owns the mandatory Apple/Google identity layer (`MANDATORY_LOGIN_PLAN.md`) —
/// every user signs in before they can create, join, or view a group. `groups`
/// is the authoritative source for "which groups am I in, as which member"
/// (`ACCOUNTS_DESIGN.md` §4, §7); there's no guest tier or separate local
/// identity store to fall back to.
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
        /// Expired, or the Apple credential was revoked / is gone — sign out.
        /// There's no guest fallback (`MANDATORY_LOGIN_PLAN.md` Part 3); the
        /// sign-in gate is all that's left to do.
        case discard
    }

    /// The "2nd group or 7 days" threshold for the one-time sync nudge
    /// (`ACCOUNTS_DESIGN.md` §10).
    static let nudgeAfter: TimeInterval = 7 * 24 * 60 * 60
    static let nudgeGroupCount = 2

    private let client: ClanTabClient
    private let sessionStore: SessionStoring
    private let knownGroups: KnownGroupsStoring
    private let syncNudge: SyncNudgeStoring
    /// Injectable so tests don't need a real Apple credential. Returns `.noSession`
    /// when there's nothing stored to check.
    private let credentialStanding: @Sendable (_ appleUserID: String) async -> CredentialStanding

    private(set) var session: StoredSession?
    /// The identity's groups from the last sign-in / `myGroups` fetch. The
    /// authoritative list for a signed-in user (`ACCOUNTS_DESIGN.md` §7) —
    /// `GroupViewModel.myIdentity` reads this directly
    /// (`MANDATORY_LOGIN_PLAN.md` Part 3; there's no separate local identity
    /// store anymore). Also mirrored into `knownGroups` for the start screen's
    /// offline-friendly list.
    private(set) var groups: [GroupMembershipSummary] = []
    private(set) var isBusy = false
    private(set) var errorMessage: String?
    /// Mirrors `syncNudge.isDismissed()` so a dismissal re-renders observers.
    private(set) var syncNudgeDismissed: Bool

    var isSignedIn: Bool { session != nil }

    init(
        client: ClanTabClient,
        sessionStore: SessionStoring,
        knownGroups: KnownGroupsStoring,
        syncNudge: SyncNudgeStoring,
        credentialStanding: @escaping @Sendable (_ appleUserID: String) async -> CredentialStanding = AuthViewModel.liveCredentialStanding
    ) {
        self.client = client
        self.sessionStore = sessionStore
        self.knownGroups = knownGroups
        self.syncNudge = syncNudge
        self.credentialStanding = credentialStanding
        self.session = sessionStore.load()
        self.syncNudgeDismissed = syncNudge.isDismissed()
    }

    // MARK: - Sync nudge (ACCOUNTS_DESIGN.md §10)
    //
    // NOTE: unreachable since `MANDATORY_LOGIN_PLAN.md` Part 3 — `StartView`
    // and `RootView` now gate every path into a group behind `isSignedIn`, so
    // `!isSignedIn` below can no longer be true inside Group Home. Left as-is
    // deliberately (out of Part 3's scope, itself harmless); worth deleting
    // this whole apparatus (this method, `dismissSyncNudge`, `syncNudge`,
    // `SyncNudgeCard`) in a followup rather than as a side effect of Part 3.

    /// Whether Group Home should show the one-time "sign in to keep your groups"
    /// card: only for a guest who hasn't dismissed it, once they've reached a
    /// 2nd group or 7 days of use.
    func shouldShowSyncNudge(now: Date = Date()) -> Bool {
        guard !isSignedIn, !syncNudgeDismissed else { return false }
        guard let firstLaunch = syncNudge.firstLaunchAt() else { return false }
        let reachedTwoGroups = knownGroups.all().count >= Self.nudgeGroupCount
        let reachedSevenDays = now.timeIntervalSince(firstLaunch) >= Self.nudgeAfter
        return reachedTwoGroups || reachedSevenDays
    }

    func dismissSyncNudge() {
        syncNudge.dismiss()
        syncNudgeDismissed = true
    }

    // MARK: - Sign in / out

    /// Exchange a verified Apple credential for a session (`ACCOUNTS_DESIGN.md` §5).
    /// `userID` is `ASAuthorizationAppleIDCredential.user` — stored for the
    /// launch-time credential-state check.
    func signIn(identityToken: String, userID: String, authorizationCode: String? = nil) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.signInWithApple(
                identityToken: identityToken,
                authorizationCode: authorizationCode
            )
            let session = StoredSession(
                token: response.sessionToken,
                provider: .apple,
                appleUserID: userID,
                expiresAt: response.expiresAt
            )
            sessionStore.save(session)
            self.session = session
            applyGroups(response.groups ?? [])
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    /// Exchange a verified Google credential for a session
    /// (`MANDATORY_LOGIN_PLAN.md` Part 1). No `userID` to store — Google has no
    /// client-side revocation check equivalent to Apple's `getCredentialState`,
    /// so a Google session relies on token expiry alone (see `handleLaunch`).
    func signInWithGoogle(identityToken: String) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.signInWithGoogle(identityToken: identityToken)
            let session = StoredSession(token: response.sessionToken, provider: .google, expiresAt: response.expiresAt)
            sessionStore.save(session)
            self.session = session
            applyGroups(response.groups ?? [])
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
        }
    }

    /// Pull the authoritative group list for the current session and mirror it
    /// into the local stores (`ACCOUNTS_DESIGN.md` §7). Called on launch and
    /// after a claim. Silent — a failure just leaves the cached list in place.
    func refreshGroups() async {
        guard let token = session?.token else { return }
        do {
            applyGroups(try await client.myGroups(token: token).groups)
        } catch ClanTabClientError.server(let code, _) where code == "INVALID_SESSION" {
            signOut()
        } catch {
            // Transient — keep the cached list.
        }
    }

    /// Link a placeholder member in `groupId` to the signed-in identity
    /// (`ACCOUNTS_DESIGN.md` §6). On success `groups` is updated locally right
    /// away (so Group Home greets them immediately, even if the follow-up
    /// refresh below is transiently unreachable) and the authoritative list is
    /// then refreshed. Returns whether it succeeded; on failure `errorMessage`
    /// carries the reason.
    func claim(groupId: String, memberId: String) async -> Bool {
        guard let token = session?.token else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let response = try await client.claimMember(groupId: groupId, memberId: memberId, token: token)
            upsertGroup(GroupMembershipSummary(groupId: groupId, memberId: response.member.id, displayName: response.member.displayName))
            knownGroups.remember(groupId: groupId)
            await refreshGroups()
            return true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            return false
        }
    }

    /// Store the server list and mirror the groupIds into `knownGroups` so the
    /// start screen's list works even before the network round-trip resolves.
    private func applyGroups(_ summaries: [GroupMembershipSummary]) {
        groups = summaries
        for summary in summaries {
            knownGroups.remember(groupId: summary.groupId)
        }
    }

    /// Insert or replace one entry in `groups` by `groupId`, for immediate
    /// local feedback ahead of a full `refreshGroups()`.
    private func upsertGroup(_ summary: GroupMembershipSummary) {
        if let index = groups.firstIndex(where: { $0.groupId == summary.groupId }) {
            groups[index] = summary
        } else {
            groups.insert(summary, at: 0)
        }
    }

    /// Drop the local session — back to the sign-in gate (no guest fallback,
    /// `MANDATORY_LOGIN_PLAN.md` Part 3). There is no server-side revocation
    /// (`ACCOUNTS_DESIGN.md` §3); the token simply expires on its own.
    func signOut() {
        sessionStore.clear()
        session = nil
        groups = []
    }

    /// Delete the account (Apple Guideline 5.1.1(v), `ACCOUNTS_DESIGN.md` §11):
    /// every claimed membership reverts to a placeholder and the server-side
    /// index is wiped. Groups, members, and expenses are untouched — signing
    /// back in (same or different identity) is required to see them again,
    /// same as any other sign-out. Returns whether it succeeded.
    func deleteAccount() async -> Bool {
        guard let token = session?.token else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await client.deleteAccount(token: token)
            signOut()
            return true
        } catch ClanTabClientError.server(let code, _) where code == "INVALID_SESSION" {
            // Already gone server-side — treat as done.
            signOut()
            return true
        } catch {
            errorMessage = Self.friendlyMessage(for: error)
            return false
        }
    }

    // MARK: - Launch

    /// On every launch: restore the session, verify the Apple credential is still
    /// good, and refresh the token if it's near expiry.
    func handleLaunch() async {
        syncNudge.recordFirstLaunch(Date()) // no-op after the first launch
        session = sessionStore.load()
        guard let current = session else { return }

        // Google has no client-side revocation check — `.noSession` here is a
        // harmless placeholder; `launchDecision` ignores `standing` entirely for
        // a Google session and goes by expiry alone.
        let standing = current.provider == .apple
            ? await credentialStanding(current.appleUserID ?? "")
            : .noSession
        switch Self.launchDecision(session: current, standing: standing, now: Date()) {
        case .none, .keep:
            break
        case .discard:
            signOut()
            return
        case .refresh:
            await refreshSession()
        }
        // Session survived — refresh the authoritative group list (§7).
        if session != nil {
            await refreshGroups()
        }
    }

    /// Pure launch-time policy (`ACCOUNTS_DESIGN.md` §3).
    nonisolated static func launchDecision(session: StoredSession?, standing: CredentialStanding, now: Date) -> LaunchDecision {
        guard let session else { return .none }
        if session.isExpired(now: now) { return .discard }
        switch session.provider {
        case .google:
            // No client-side revocation check for Google — expiry is the only signal.
            return session.needsRefresh(now: now) ? .refresh : .keep
        case .apple:
            switch standing {
            case .revoked, .notFound:
                return .discard
            case .noSession, .authorized:
                return session.needsRefresh(now: now) ? .refresh : .keep
            }
        }
    }

    private func refreshSession() async {
        guard let current = session else { return }
        do {
            let response = try await client.refreshSession(token: current.token)
            let updated = StoredSession(
                token: response.sessionToken,
                provider: current.provider,
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
            switch code {
            case "INVALID_APPLE_TOKEN":
                return "That Apple sign-in couldn't be verified. Please try again."
            case "INVALID_GOOGLE_TOKEN":
                return "That Google sign-in couldn't be verified. Please try again."
            default:
                return message
            }
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
