import SwiftUI
import ClanTabKit

struct RootView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel
    let onboarding: OnboardingStoring

    @State private var route: AppRoute = .start
    @State private var showingSettings = false
    /// The first-run walkthrough (`CHECKLIST.md` "Onboarding walkthrough") —
    /// shown over everything else until it's finished or skipped, once.
    @State private var showOnboarding: Bool
    /// Set when the Home Screen "Add Expense" quick action targets a group we
    /// then route into — `GroupHomeView` opens Add Expense for it once.
    @State private var pendingAddExpenseGroupId: String?

    init(client: ClanTabClient, knownGroups: KnownGroupsStoring, auth: AuthViewModel, onboarding: OnboardingStoring) {
        self.client = client
        self.knownGroups = knownGroups
        self.auth = auth
        self.onboarding = onboarding
        _showOnboarding = State(initialValue: Self.shouldPresentOnboarding(onboarding))
    }

    /// Whether the first-run walkthrough is presented on launch: only until
    /// it's been finished or skipped once. Pure, so the routing rule can be
    /// tested without standing up the view.
    static func shouldPresentOnboarding(_ store: OnboardingStoring) -> Bool {
        !store.hasCompletedOnboarding()
    }
    /// A deep link opened while signed out (`MANDATORY_LOGIN_PLAN.md` Part 3 —
    /// viewing a group requires signing in first). Resumed once sign-in succeeds.
    @State private var pendingDeepLink: (groupId: String, accessToken: String?)?
    /// Bumped when the local group list changes without an `auth.groups` change
    /// (removing a group locally), to recompute `yourGroups`.
    @State private var knownGroupsRevision = 0

    var body: some View {
        NavigationStack {
            // Key the whole route subtree on `route`. SwiftUI otherwise treats
            // two hits of the same `switch` case as one view identity — so a
            // `.group("A")` → `.group("B")` switch, or a `.claimMember` screen
            // re-targeted by a second deep link, never re-runs the child's
            // `init` and its `@State` (`GroupHomeView.viewModel`,
            // `ClaimMemberView.members`, …) stays pinned to the first value.
            // `.id(route)` forces a teardown/rebuild whenever the associated
            // values change (`CHECKLIST.md` "Fix: group switching…" + the
            // same-view-identity audit).
            content
                .id(route)
        }
        .task {
            await auth.handleLaunch()
            resolveInitialRoute()
            refreshQuickAction()
            // A quick action that cold-launched the app, buffered until now
            // (`CHECKLIST.md` "Home Screen quick action").
            if let groupId = QuickActions.consumePending() {
                handleQuickActionAddExpense(groupId: groupId)
            }
            // A `clantab://` or Universal Link that cold-launched the app,
            // buffered by `SceneDelegate` (`CHECKLIST.md` "Custom domain +
            // Universal Links").
            if let url = IncomingURL.consumePending() {
                handleDeepLink(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .urlOpened)) { notification in
            // Every warm-open link — `clantab://` scheme or tapped Universal
            // Link — routed through `SceneDelegate` → `IncomingURL`.
            guard let url = notification.userInfo?["url"] as? URL else { return }
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { notification in
            // A tapped push is handled exactly like any other incoming URL
            // (`AppDelegate`, `FEATURE_BACKLOG.md` "Push notifications").
            guard let url = notification.userInfo?["url"] as? URL else { return }
            handleDeepLink(url)
        }
        .onReceive(NotificationCenter.default.publisher(for: .quickActionAddExpense)) { notification in
            guard let groupId = notification.userInfo?[QuickActions.groupIdKey] as? String else { return }
            handleQuickActionAddExpense(groupId: groupId)
        }
        .onChange(of: auth.isSignedIn) { _, _ in refreshQuickAction() }
        .onChange(of: auth.groups) { _, _ in refreshQuickAction() }
        .onChange(of: knownGroupsRevision) { _, _ in refreshQuickAction() }
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
            .materialSheet()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                onboarding.markOnboardingComplete()
                showOnboarding = false
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
                initialAction: pendingAddExpenseGroupId == groupId ? .addExpense : nil,
                onInitialActionConsumed: { pendingAddExpenseGroupId = nil },
                onOpenSettings: { showingSettings = true },
                onSwitchGroup: { enterGroup($0, accessToken: knownAccessToken(for: $0)) },
                onCreateNewGroup: { route = .createGroup },
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
        refreshQuickAction()
    }

    /// The Home Screen "Add Expense" quick action (`CHECKLIST.md`) fired for
    /// `groupId`: open it, and flag it so `GroupHomeView` presents Add Expense
    /// once. Falls back to the start screen if the group isn't ours (a stale
    /// shortcut after leaving it).
    private func handleQuickActionAddExpense(groupId: String) {
        showOnboarding = false
        showingSettings = false
        guard auth.isSignedIn, isMember(groupId) else { route = .start; return }
        pendingAddExpenseGroupId = groupId
        enterGroup(groupId, accessToken: knownAccessToken(for: groupId))
    }

    /// Keep the Home Screen quick action pointed at the current primary group
    /// — only while signed in, so a signed-out device offers nothing.
    private func refreshQuickAction() {
        QuickActions.refresh(auth.isSignedIn ? knownGroups.all() : [])
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

    /// Recognizes both the Universal Link (`https://clantab.nakka.dev/g/:groupId`,
    /// per `DESIGN.md` §1) and the `clantab://g/:groupId` fallback scheme —
    /// the latter is also the only form testable in the Simulator, which can't
    /// associate the domain without a provisioned entitlement.
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
