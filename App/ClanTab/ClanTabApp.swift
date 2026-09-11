import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let client: ClanTabClient
    private let knownGroups: KnownGroupsStoring
    private let onboarding: OnboardingStoring
    private let whatsNew: WhatsNewStoring
    private let returnGap: ReturnGapStoring
    @State private var auth: AuthViewModel
    @State private var avatarImageLoader: AvatarImageLoader
    @AppStorage("clantab.theme") private var theme = AppTheme.system

    init() {
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        let knownGroups = UserDefaultsKnownGroupsStore()
        self.client = client
        self.knownGroups = knownGroups
        self.onboarding = UserDefaultsOnboardingStore()
        self.whatsNew = UserDefaultsWhatsNewStore()
        self.returnGap = UserDefaultsReturnGapStore()
        let auth = AuthViewModel(
            client: client,
            sessionStore: KeychainSessionStore(),
            knownGroups: knownGroups,
            syncNudge: UserDefaultsSyncNudgeStore(),
            backupNudge: UserDefaultsBackupNudgeStore(),
            balanceAging: .live
        )
        _auth = State(initialValue: auth)
        _avatarImageLoader = State(initialValue: AvatarImageLoader(client: client, auth: auth))
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                client: client, knownGroups: knownGroups, auth: auth, avatarImageLoader: avatarImageLoader,
                onboarding: onboarding, whatsNew: whatsNew, returnGap: returnGap
            )
                .preferredColorScheme(theme.colorScheme)
                .task {
                    appDelegate.authViewModel = auth
                    appDelegate.knownGroups = knownGroups
                }
        }
    }
}
