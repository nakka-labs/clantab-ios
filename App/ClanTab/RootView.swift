import SwiftUI
import ClanTabKit

struct RootView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel
    let avatarImageLoader: AvatarImageLoader
    let onboarding: OnboardingStoring
    let whatsNew: WhatsNewStoring

    @State private var route: AppRoute = .start
    @State private var showingSettings = false
    /// The first-run walkthrough (`CHECKLIST.md` "Onboarding walkthrough") —
    /// shown over everything else until it's finished or skipped, once.
    @State private var showOnboarding: Bool
    /// The "What's New" sheet (`CHECKLIST.md` "'What's New' sheet, versioned")
    /// — evaluated once in the launch `.task` below (not `init`: it advances
    /// `whatsNew`'s stored build, a side effect that must run at most once
    /// per launch, not on every `init` SwiftUI happens to re-run).
    @State private var showWhatsNew = false
    @State private var whatsNewReleases: [WhatsNewRelease] = []
    /// Set when the Home Screen "Add Expense" quick action targets a group we
    /// then route into — `GroupHomeView` opens Add Expense for it once.
    @State private var pendingAddExpenseGroupId: String?

    init(
        client: ClanTabClient,
        knownGroups: KnownGroupsStoring,
        auth: AuthViewModel,
        avatarImageLoader: AvatarImageLoader,
        onboarding: OnboardingStoring,
        whatsNew: WhatsNewStoring
    ) {
        self.client = client
        self.knownGroups = knownGroups
        self.auth = auth
        self.avatarImageLoader = avatarImageLoader
        self.onboarding = onboarding
        self.whatsNew = whatsNew
        _showOnboarding = State(initialValue: Self.shouldPresentOnboarding(onboarding))
    }

    /// Whether the first-run walkthrough is presented on launch: only until
    /// it's been finished or skipped once. Pure, so the routing rule can be
    /// tested without standing up the view.
    static func shouldPresentOnboarding(_ store: OnboardingStoring) -> Bool {
        !store.hasCompletedOnboarding()
    }

    /// `CFBundleVersion`, parsed to an `Int` — `0` if it's somehow missing or
    /// non-numeric (never crashes the "What's New" check over it).
    static func currentBuildNumber() -> Int {
        Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
    }

    /// The route to show on launch given the saved launch-screen preference
    /// (`CHECKLIST.md` "Settings: launch-screen preference"). `nil` means "stay
    /// on the dashboard" — either that's the preference (`""`), or the pinned
    /// group is gone / the user is signed out, in which case the caller also
    /// clears the stale preference. Pure, so it's testable without a host view.
    static func launchRoute(
        preferredGroupId: String,
        isSignedIn: Bool,
        isKnownGroup: (String) -> Bool
    ) -> AppRoute? {
        guard isSignedIn, !preferredGroupId.isEmpty, isKnownGroup(preferredGroupId) else { return nil }
        return .group(groupId: preferredGroupId)
    }
    /// A deep link opened while signed out (`MANDATORY_LOGIN_PLAN.md` Part 3 —
    /// viewing a group requires signing in first). Resumed once sign-in succeeds.
    @State private var pendingDeepLink: (groupId: String, accessToken: String?)?
    /// Bumped when the local group list changes without an `auth.groups` change
    /// (removing a group locally), to recompute `yourGroups`.
    @State private var knownGroupsRevision = 0
    /// The launch-screen preference (`CHECKLIST.md` "Settings: launch-screen
    /// preference"), set in `SettingsView`. `""` — land on the dashboard
    /// (`StartView`); a groupId — open straight into that group.
    @AppStorage("clantab.launchGroupId") private var launchGroupId = ""

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
                .transition(Self.routeTransition)
        }
        .environment(\.avatarImageLoader, avatarImageLoader)
        .task {
            await auth.handleLaunch()
            // Launch routing: the dashboard (`StartView`) by default, or
            // straight into a group the user pinned in Settings (`CHECKLIST.md`
            // "Settings: launch-screen preference"). A pin to a group that's no
            // longer known (left it, or a different account) falls back to the
            // dashboard and clears itself. Deep links, push taps and the Home
            // Screen quick action below still route on their own.
            if let launch = Self.launchRoute(
                preferredGroupId: launchGroupId,
                isSignedIn: auth.isSignedIn,
                isKnownGroup: { id in knownGroups.all().contains { $0.groupId == id } }
            ) {
                route = launch
            } else if !launchGroupId.isEmpty, auth.isSignedIn,
                      !knownGroups.all().contains(where: { $0.groupId == launchGroupId }) {
                launchGroupId = ""
            }
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
            // Time-boxed dashboard fallback sync — catches balances a missed or
            // denied push never delivered (`CHECKLIST.md` "Dashboard fallback
            // sync for missed/denied push"). No-op unless it's actually stale.
            await auth.reconcileGroupBalances(force: false)
            knownGroupsRevision += 1
            evaluateWhatsNew()
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
        .onChange(of: auth.isSignedIn) { _, signedIn in
            refreshQuickAction()
            // A new identity must never see the previous one's cached photos.
            if !signedIn { avatarImageLoader.clearAll() }
        }
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
                SettingsView(auth: auth, client: client, knownGroups: knownGroups, onDone: { showingSettings = false })
            }
            .environment(\.avatarImageLoader, avatarImageLoader)
            .materialSheet()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                onboarding.markOnboardingComplete()
                showOnboarding = false
            }
        }
        .sheet(isPresented: $showWhatsNew, onDismiss: {
            // Fires on the "Done" button and on a swipe-to-dismiss alike, so
            // either way this build is recorded seen exactly once.
            whatsNew.markSeen(build: Self.currentBuildNumber())
        }) {
            WhatsNewView(releases: whatsNewReleases) { showWhatsNew = false }
                .materialSheet()
        }
    }

    /// Decides — and, either way, advances `whatsNew`'s stored build — whether
    /// this launch should show the "What's New" sheet (`CHECKLIST.md`).
    /// Runs once from the launch `.task`, never `init` (SwiftUI can re-run a
    /// view's `init` on its own; this method's side effect must not).
    /// A fresh install / one that predates this feature (`lastSeenBuild ==
    /// nil`) seeds itself silently instead of dumping the whole history on
    /// someone who never asked for a changelog.
    private func evaluateWhatsNew() {
        let currentBuild = Self.currentBuildNumber()
        guard let lastSeen = whatsNew.lastSeenBuild() else {
            whatsNew.markSeen(build: currentBuild)
            return
        }
        guard WhatsNew.shouldShow(lastSeenBuild: lastSeen, currentBuild: currentBuild, hasCompletedOnboarding: onboarding.hasCompletedOnboarding()) else {
            return
        }
        whatsNewReleases = WhatsNew.unseenReleases(sinceBuild: lastSeen)
        showWhatsNew = true
    }

    /// The start screen's "Your Groups" list — signed-in only
    /// (`MANDATORY_LOGIN_PLAN.md` Part 3): every group is tied to an identity
    /// now, so browsing a device's cached list while signed out isn't allowed.
    /// A private 1:1 tab (`CHECKLIST.md` "Friends/contacts list... + private
    /// 1:1 tabs") is filtered out here — the one place both the groups list
    /// and the dashboard totals draw from — reachable only via the Friends
    /// screen, never this list.
    private var yourGroups: [KnownGroup] {
        guard auth.isSignedIn else { return [] }
        _ = auth.groups
        _ = knownGroupsRevision
        return knownGroups.all().filter { !$0.isHidden }
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
                onOpenSettings: { showingSettings = true },
                onOpenFriends: { route = .friends },
                onRefresh: {
                    await auth.reconcileGroupBalances(force: true)
                    knownGroupsRevision += 1
                }
            )
        case .friends:
            FriendsView(
                auth: auth,
                onOpenGroup: { enterGroup($0) },
                onDone: { route = .start }
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
                onOpenGroupsHub: { withAnimation(.claimSettle) { route = .start } },
                onLeaveGroup: { leaveGroup(groupId) },
                onGroupUnavailable: { leaveGroup(groupId) }
            )
        }
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

    /// The spring hero for opening / leaving a group (`CHECKLIST.md`
    /// "Spring/matched-geometry transition"). A literal cross-screen
    /// `matchedGeometryEffect` isn't possible here — `.id(route)` tears the
    /// old screen down before the new one exists, so source and target are
    /// never co-present — so this is the achievable version: the incoming
    /// screen springs up from 95% with a cross-fade on `Animation.claimSettle`
    /// (that curve's own doc names this exact use). Group open/close only;
    /// the form routes (`.createGroup` etc.) stay instant.
    static let routeTransition: AnyTransition = .asymmetric(
        insertion: .scale(scale: 0.95).combined(with: .opacity),
        removal: .opacity
    )

    private func enterGroup(_ groupId: String, accessToken: String? = nil) {
        knownGroups.remember(groupId: groupId, name: nil, accessToken: accessToken, at: Date())
        withAnimation(.claimSettle) { route = .group(groupId: groupId) }
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
        withAnimation(.claimSettle) { route = .start }
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
