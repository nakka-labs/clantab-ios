import SwiftUI
import ClanTabKit

struct RootView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel

    @State private var route: AppRoute = .start
    @State private var showingSettings = false
    /// A deep link opened while signed out (`MANDATORY_LOGIN_PLAN.md` Part 3 —
    /// viewing a group requires signing in first). Resumed once sign-in succeeds.
    @State private var pendingDeepLink: (groupId: String, accessToken: String?)?
    /// Bumped when the local group list changes without an `auth.groups` change
    /// (removing a group locally), to recompute `yourGroups`.
    @State private var knownGroupsRevision = 0

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            await auth.handleLaunch()
            resolveInitialRoute()
        }
        .onOpenURL { url in handleDeepLink(url) }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, let pending = pendingDeepLink else { return }
            pendingDeepLink = nil
            if isMember(pending.groupId) {
                enterGroup(pending.groupId, accessToken: pending.accessToken)
            } else {
                route = .claimMember(groupId: pending.groupId, accessToken: pending.accessToken)
            }
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(auth: auth, client: client, onDone: { showingSettings = false })
            }
        }
    }

    /// The start screen's "Your Groups" list — signed-in only
    /// (`MANDATORY_LOGIN_PLAN.md` Part 3): every group is tied to an identity
    /// now, so browsing a device's cached list while signed out isn't allowed.
    private var yourGroups: [KnownGroup] {
        guard auth.isSignedIn else { return [] }
        _ = auth.groups
        _ = knownGroupsRevision
        return knownGroups.all()
    }

    private func isMember(_ groupId: String) -> Bool {
        auth.groups.contains { $0.groupId == groupId }
    }

    /// The locally cached access token for a group already in `knownGroups`
    /// (`ACCESS_TOKEN_PLAN.md`) — used when entering `.group` from the start
    /// screen's list, where the token isn't otherwise in hand.
    private func knownAccessToken(for groupId: String) -> String? {
        knownGroups.all().first { $0.groupId == groupId }?.accessToken
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .start:
            StartView(
                onCreate: { route = .createGroup },
                onJoinWithCode: { route = .joinGroup },
                groups: yourGroups,
                onOpenGroup: { enterGroup($0) },
                onRemoveGroup: { groupId in
                    knownGroups.forget(groupId: groupId)
                    knownGroupsRevision += 1
                },
                isSignedIn: auth.isSignedIn,
                isSigningIn: auth.isBusy,
                authError: auth.errorMessage,
                onSignIn: { identityToken, userID, authCode in
                    Task { await auth.signIn(identityToken: identityToken, userID: userID, authorizationCode: authCode) }
                },
                onSignInWithGoogle: { identityToken in
                    Task { await auth.signInWithGoogle(identityToken: identityToken) }
                },
                onOpenSettings: { showingSettings = true }
            )
        case .createGroup:
            CreateGroupView(
                client: client,
                auth: auth,
                onCreated: { enterGroup($0, accessToken: $1) },
                onCancel: { route = .start }
            )
        case .joinGroup:
            JoinGroupView(
                client: client,
                onResolved: { groupId, accessToken in
                    route = .claimMember(groupId: groupId, accessToken: accessToken)
                },
                onCancel: { route = .start }
            )
        case .claimMember(let groupId, let accessToken):
            ClaimMemberView(
                groupId: groupId,
                client: client,
                accessToken: accessToken,
                auth: auth,
                onClaimed: { enterGroup($0, accessToken: accessToken) },
                onCancel: { route = .start }
            )
        case .group(let groupId):
            GroupHomeView(
                groupId: groupId,
                client: client,
                knownGroups: knownGroups,
                auth: auth,
                accessToken: knownAccessToken(for: groupId),
                onOpenSettings: { showingSettings = true },
                onSwitchGroup: { enterGroup($0, accessToken: knownAccessToken(for: $0)) },
                onLeaveGroup: { leaveGroup(groupId) },
                onGroupUnavailable: { leaveGroup(groupId) }
            )
        }
    }

    /// On launch, skip straight back into the group this device was last active
    /// in — but only when there's exactly one, so a device that's seen several
    /// groups lands on the start screen's list instead. Runs after
    /// `auth.handleLaunch()` so `auth.groups` is populated.
    private func resolveInitialRoute() {
        guard route == .start, auth.isSignedIn else { return }
        let known = knownGroups.all()
        guard known.count == 1, let only = known.first, isMember(only.groupId) else { return }
        route = .group(groupId: only.groupId)
    }

    private func handleDeepLink(_ url: URL) {
        switch Self.resolveDeepLink(url, isMember: isMember, isSignedIn: auth.isSignedIn) {
        case .openGroup(let groupId, let accessToken): enterGroup(groupId, accessToken: accessToken)
        case .claimMember(let groupId, let accessToken): route = .claimMember(groupId: groupId, accessToken: accessToken)
        case .needsSignIn(let groupId, let accessToken):
            pendingDeepLink = (groupId, accessToken)
            route = .start
        case nil: break
        }
    }

    private func enterGroup(_ groupId: String, accessToken: String? = nil) {
        knownGroups.remember(groupId: groupId, name: nil, accessToken: accessToken, at: Date())
        route = .group(groupId: groupId)
    }

    /// Drop a group from this device's local list — on an explicit "Leave This
    /// Group" or a 404 (its capability URL is gone) alike. Purely a local-list
    /// removal: it doesn't unlink a claimed membership server-side, so a
    /// signed-in member's next `refreshGroups()` can bring it right back
    /// (pre-existing behavior, unchanged by `MANDATORY_LOGIN_PLAN.md` Part 3).
    private func leaveGroup(_ groupId: String) {
        knownGroups.forget(groupId: groupId)
        route = .start
    }

    /// Where a `/g/:groupId` link should land. Pure so it can be tested without a
    /// hosting view:
    /// - signed in and already a member → straight into the group;
    /// - signed in, no membership yet → the claim-or-join-fresh screen (`ACCOUNTS_DESIGN.md` §6);
    /// - signed out → nothing to do until they sign in (`MANDATORY_LOGIN_PLAN.md` Part 3).
    ///
    /// Each case carries the link's `accessToken` (`ACCESS_TOKEN_PLAN.md`), if
    /// any, straight through to wherever it's needed next.
    enum DeepLinkResolution: Equatable {
        case openGroup(groupId: String, accessToken: String?)
        case claimMember(groupId: String, accessToken: String?)
        case needsSignIn(groupId: String, accessToken: String?)
    }

    nonisolated static func resolveDeepLink(
        _ url: URL,
        isMember: (String) -> Bool,
        isSignedIn: Bool
    ) -> DeepLinkResolution? {
        guard let groupId = extractGroupId(from: url) else { return nil }
        let accessToken = extractAccessToken(from: url)
        guard isSignedIn else { return .needsSignIn(groupId: groupId, accessToken: accessToken) }
        return isMember(groupId)
            ? .openGroup(groupId: groupId, accessToken: accessToken)
            : .claimMember(groupId: groupId, accessToken: accessToken)
    }

    /// Recognizes both a real capability link (`https://<host>/g/:groupId`, per
    /// `DESIGN.md` §1) and the `clantab://g/:groupId` scheme registered in
    /// `project.yml` for Simulator testing before a production domain exists.
    nonisolated static func extractGroupId(from url: URL) -> String? {
        if url.scheme == "clantab", url.host == "g" {
            return url.pathComponents.dropFirst().first
        }
        let components = url.pathComponents.filter { $0 != "/" }
        if let index = components.firstIndex(of: "g"), components.indices.contains(index + 1) {
            return components[index + 1]
        }
        return nil
    }

    /// The `?token=` query item (`ACCESS_TOKEN_PLAN.md`) — `nil` for a link to
    /// a group that predates the feature and was never regenerated.
    nonisolated static func extractAccessToken(from url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "token" }?
            .value
    }
}
