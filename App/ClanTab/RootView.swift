import SwiftUI
import ClanTabKit

struct RootView: View {
    let client: ClanTabClient
    let identityStore: IdentityStoring
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel

    @State private var route: AppRoute = .start
    @State private var showingSettings = false
    /// Bumped when the local group list changes without an `auth.groups` change
    /// (a guest removing a group), to recompute `yourGroups`.
    @State private var knownGroupsRevision = 0

    var body: some View {
        NavigationStack {
            content
        }
        .task {
            resolveInitialRoute()
            await auth.handleLaunch()
        }
        .onOpenURL { url in handleDeepLink(url) }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView(auth: auth, client: client, onDone: { showingSettings = false })
            }
        }
    }

    /// The start screen's "Your Groups" list. Reading `auth.groups` here keeps
    /// this recomputing after a signed-in launch seeds new groups into
    /// `knownGroups` (which isn't itself observable).
    private var yourGroups: [KnownGroup] {
        _ = auth.groups
        _ = knownGroupsRevision
        return knownGroups.all()
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .start:
            StartView(
                onCreate: { route = .createGroup },
                onJoinWithCode: { route = .joinGroup(groupId: nil) },
                groups: yourGroups,
                onOpenGroup: enterGroup,
                onRemoveGroup: { groupId in
                    knownGroups.forget(groupId: groupId)
                    identityStore.removeIdentity(forGroup: groupId)
                    knownGroupsRevision += 1
                },
                isSignedIn: auth.isSignedIn,
                signedInProvider: auth.session?.provider,
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
                identityStore: identityStore,
                onCreated: enterGroup,
                onCancel: { route = .start }
            )
        case .joinGroup(let groupId):
            JoinGroupView(
                groupId: groupId,
                client: client,
                identityStore: identityStore,
                onJoined: enterGroup,
                onCancel: { route = .start }
            )
        case .chooseJoin(let groupId):
            JoinChoiceView(
                onThisIsMe: { route = .claimMember(groupId: groupId) },
                onJoinAsGuest: { route = .joinGroup(groupId: groupId) },
                onCancel: { route = .start }
            )
        case .claimMember(let groupId):
            ClaimMemberView(
                groupId: groupId,
                client: client,
                auth: auth,
                onClaimed: enterGroup,
                onJoinAsGuest: { route = .joinGroup(groupId: groupId) },
                onCancel: { route = .chooseJoin(groupId: groupId) }
            )
        case .group(let groupId):
            GroupHomeView(
                groupId: groupId,
                client: client,
                identityStore: identityStore,
                knownGroups: knownGroups,
                auth: auth,
                onOpenSettings: { showingSettings = true },
                onLeaveGroup: { leaveGroup(groupId, forgetIdentity: true) },
                onGroupUnavailable: { leaveGroup(groupId) }
            )
        }
    }

    /// On launch, skip straight back into the group this device was last active
    /// in — but only when there's exactly one, so a device that's seen several
    /// groups lands on the start screen's list instead.
    private func resolveInitialRoute() {
        guard route == .start else { return }
        let known = knownGroups.all()
        guard known.count == 1, let only = known.first,
              identityStore.identity(forGroup: only.groupId) != nil
        else { return }
        route = .group(groupId: only.groupId)
    }

    private func handleDeepLink(_ url: URL) {
        switch Self.resolveDeepLink(
            url,
            hasIdentity: { identityStore.identity(forGroup: $0) != nil },
            isSignedIn: auth.isSignedIn
        ) {
        case .openGroup(let groupId): enterGroup(groupId)
        case .chooseJoin(let groupId): route = .chooseJoin(groupId: groupId)
        case .joinGroup(let groupId): route = .joinGroup(groupId: groupId)
        case nil: break
        }
    }

    private func enterGroup(_ groupId: String) {
        knownGroups.remember(groupId: groupId, name: nil, at: Date())
        route = .group(groupId: groupId)
    }

    /// Drop a group from this device: on a 404 (its capability URL is gone) the
    /// local identity is left in place — harmless, still valid if the group
    /// becomes reachable again. On an explicit "Leave This Group"
    /// (`forgetIdentity: true`) the identity is cleared too, so re-opening the
    /// link starts a fresh join.
    private func leaveGroup(_ groupId: String, forgetIdentity: Bool = false) {
        knownGroups.forget(groupId: groupId)
        if forgetIdentity { identityStore.removeIdentity(forGroup: groupId) }
        route = .start
    }

    /// Where a `/g/:groupId` link should land. Pure so it can be tested without a
    /// hosting view:
    /// - already a member on this device → straight into the group;
    /// - no membership, signed in → the claim-or-join chooser (`ACCOUNTS_DESIGN.md` §6);
    /// - no membership, guest → the join-as-guest flow.
    enum DeepLinkResolution: Equatable {
        case openGroup(String)
        case chooseJoin(String)
        case joinGroup(String)
    }

    nonisolated static func resolveDeepLink(
        _ url: URL,
        hasIdentity: (String) -> Bool,
        isSignedIn: Bool
    ) -> DeepLinkResolution? {
        guard let groupId = extractGroupId(from: url) else { return nil }
        if hasIdentity(groupId) { return .openGroup(groupId) }
        return isSignedIn ? .chooseJoin(groupId) : .joinGroup(groupId)
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
}
