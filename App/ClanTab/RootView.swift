import SwiftUI
import ClanTabKit

struct RootView: View {
    let client: ClanTabClient
    let knownGroups: KnownGroupsStoring
    let auth: AuthViewModel
    let avatarImageLoader: AvatarImageLoader
    let onboarding: OnboardingStoring
    let whatsNew: WhatsNewStoring
    let returnGap: ReturnGapStoring

    /// The persistent 4-tab shell (`CHECKLIST.md` UX audit [6]) — which tab is
    /// selected, independent of what's pushed below it.
    @State private var selectedTab: MainTab = .home
    /// The Home tab's own push stack — group drill-down, Add/Join a group,
    /// and the claim-member screen all live here now (`AppRoute`'s doc
    /// comment). Opening a group from *any* tab switches to Home and pushes
    /// here, so there's only ever one place a group screen can be.
    @State private var homeStack: [AppRoute] = []
    /// The first-run walkthrough (`CHECKLIST.md` "Onboarding walkthrough") —
    /// shown over everything else until it's finished or skipped, once.
    @State private var showOnboarding: Bool
    /// The "What's New" sheet (`CHECKLIST.md` "'What's New' sheet, versioned")
    /// — evaluated once in the launch `.task` below (not `init`: it advances
    /// `whatsNew`'s stored build, a side effect that must run at most once
    /// per launch, not on every `init` SwiftUI happens to re-run).
    @State private var showWhatsNew = false
    @State private var whatsNewReleases: [WhatsNewRelease] = []
    /// The one-time "Welcome back" balance summary (`CHECKLIST.md`
    /// "Returning-user balance summary") — same once-per-launch-evaluation
    /// shape as `showWhatsNew`, decided in the launch `.task`.
    @State private var showWelcomeBack = false
    /// Set once by `ClanTabApp` via `.environment(\.coachMarks, ...)` on this
    /// view — read back here just to pass on to `SettingsView`'s "Show tips
    /// again" (`CHECKLIST.md`); every other coach-mark call site reads the
    /// environment directly, no threading needed.
    @Environment(\.coachMarks) private var coachMarks
    /// Set when the Home Screen "Add Expense" quick action targets a group we
    /// then route into — `GroupHomeView` opens Add Expense for it once.
    @State private var pendingAddExpenseGroupId: String?

    init(
        client: ClanTabClient,
        knownGroups: KnownGroupsStoring,
        auth: AuthViewModel,
        avatarImageLoader: AvatarImageLoader,
        onboarding: OnboardingStoring,
        whatsNew: WhatsNewStoring,
        returnGap: ReturnGapStoring
    ) {
        self.client = client
        self.knownGroups = knownGroups
        self.auth = auth
        self.avatarImageLoader = avatarImageLoader
        self.onboarding = onboarding
        self.whatsNew = whatsNew
        self.returnGap = returnGap
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

    /// The Home-tab destination to push on launch given the saved
    /// launch-screen preference (`CHECKLIST.md` "Settings: launch-screen
    /// preference"). `nil` means "stay on the dashboard" — either that's the
    /// preference (`""`), or the pinned group is gone / the user is signed
    /// out, in which case the caller also clears the stale preference. Pure,
    /// so it's testable without a host view.
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
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homeStack) {
                StartView(
                    onCreate: { homeStack.append(.createGroup) },
                    onJoinWithCode: { homeStack.append(.joinGroup) },
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
                    onRefresh: {
                        await auth.reconcileGroupBalances(force: true)
                        knownGroupsRevision += 1
                    },
                    showWelcomeBack: showWelcomeBack,
                    onDismissWelcomeBack: { showWelcomeBack = false }
                )
                .navigationDestination(for: AppRoute.self) { route in homeDestination(route) }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(MainTab.home)

            // Friends/Insights need a signed-in identity to mean anything
            // (`AGENTS.md` "Mandatory identity") — hidden rather than shown
            // empty pre-auth, same call as the old hard sign-in wall on
            // `StartView` itself.
            if auth.isSignedIn {
                NavigationStack {
                    FriendsView(auth: auth, onOpenGroup: { enterGroup($0) })
                }
                .tabItem { Label("Friends", systemImage: "person.2") }
                .tag(MainTab.friends)

                NavigationStack {
                    InsightsHubView(client: client, knownGroups: knownGroups)
                }
                .tabItem { Label("Insights", systemImage: "chart.bar") }
                .tag(MainTab.insights)
            }

            NavigationStack {
                SettingsView(
                    auth: auth, client: client, knownGroups: knownGroups,
                    onboarding: onboarding, coachMarks: coachMarks,
                    onDone: { selectedTab = .home }
                )
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(MainTab.settings)
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
                homeStack = [launch]
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
            evaluateWelcomeBack()
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
            if !signedIn {
                // A new identity must never see the previous one's cached
                // photos, and there's no guest tier to fall back to viewing
                // (`AGENTS.md`) — drop back to the Home tab's root and clear
                // whatever was pushed under it.
                avatarImageLoader.clearAll()
                selectedTab = .home
                homeStack = []
            }
        }
        .onChange(of: auth.groups) { _, _ in refreshQuickAction() }
        .onChange(of: knownGroupsRevision) { _, _ in refreshQuickAction() }
        .onChange(of: auth.isSignedIn) { _, signedIn in
            guard signedIn, let pending = pendingDeepLink else { return }
            pendingDeepLink = nil
            if isMember(pending.groupId) {
                enterGroup(pending.groupId, accessToken: pending.accessToken)
            } else {
                selectedTab = .home
                homeStack = [.claimMember(groupId: pending.groupId, accessToken: pending.accessToken)]
            }
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

    /// Decides whether this launch shows the "Welcome back" balance summary
    /// (`CHECKLIST.md` "Returning-user balance summary"), then always records
    /// this open — whether or not the card ends up shown — so the gap resets
    /// and the next launch measures from *this* one, same one-time-per-gap
    /// shape as `BackupNudge`'s own recurring "last shown" clock.
    private func evaluateWelcomeBack() {
        showWelcomeBack = auth.isSignedIn && ReturnGap.shouldShowWelcomeBack(lastOpenAt: returnGap.lastOpenAt())
        returnGap.recordOpen()
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

    /// Everything pushed under the Home tab (`AppRoute`'s doc comment) —
    /// `NavigationStack`'s own value-based push identity means two different
    /// `.group(groupId:)` values are naturally distinct destinations with
    /// fresh `@State`, so the old `.id(route)` same-case-identity workaround
    /// (`CHECKLIST.md` "Fix: group switching…") isn't needed here anymore.
    @ViewBuilder
    private func homeDestination(_ route: AppRoute) -> some View {
        switch route {
        case .createGroup:
            CreateGroupView(
                client: client,
                auth: auth,
                onCreated: { enterGroup($0, accessToken: $1) },
                onCancel: { if !homeStack.isEmpty { homeStack.removeLast() } }
            )
        case .joinGroup:
            JoinGroupView(
                client: client,
                onResolved: { groupId, accessToken in
                    homeStack.append(.claimMember(groupId: groupId, accessToken: accessToken))
                },
                onCancel: { if !homeStack.isEmpty { homeStack.removeLast() } }
            )
        case .claimMember(let groupId, let accessToken):
            ClaimMemberView(
                groupId: groupId,
                client: client,
                accessToken: accessToken,
                auth: auth,
                onClaimed: { enterGroup($0, accessToken: accessToken) },
                onCancel: { homeStack = [] }
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
                onLeaveGroup: { leaveGroup(groupId) },
                onGroupUnavailable: { leaveGroup(groupId) }
            )
        }
    }

    private func handleDeepLink(_ url: URL) {
        switch Self.resolveDeepLink(url, isMember: isMember, isSignedIn: auth.isSignedIn) {
        case .openGroup(let groupId, let accessToken): enterGroup(groupId, accessToken: accessToken)
        case .claimMember(let groupId, let accessToken):
            selectedTab = .home
            homeStack = [.claimMember(groupId: groupId, accessToken: accessToken)]
        case .needsSignIn(let groupId, let accessToken):
            pendingDeepLink = (groupId, accessToken)
            selectedTab = .home
            homeStack = []
        case nil: break
        }
    }

    private func enterGroup(_ groupId: String, accessToken: String? = nil) {
        knownGroups.remember(groupId: groupId, name: nil, accessToken: accessToken, at: Date())
        selectedTab = .home
        // A flat reset, not an append — reached from a group row (stack
        // already empty), the create/join chain (drops those forms from the
        // back-stack, matching the old full-route-swap behavior), or another
        // tab entirely (Friends). Either way landing straight on the group is
        // the right outcome, and NavigationStack animates the transition on
        // its own now that this is a genuine push, not a content swap.
        homeStack = [.group(groupId: groupId)]
        refreshQuickAction()
    }

    /// The Home Screen "Add Expense" quick action (`CHECKLIST.md`) fired for
    /// `groupId`: open it, and flag it so `GroupHomeView` presents Add Expense
    /// once. Falls back to the Home tab's root if the group isn't ours (a
    /// stale shortcut after leaving it).
    private func handleQuickActionAddExpense(groupId: String) {
        showOnboarding = false
        guard auth.isSignedIn, isMember(groupId) else {
            selectedTab = .home
            homeStack = []
            return
        }
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
        homeStack = []
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
