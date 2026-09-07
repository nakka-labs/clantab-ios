import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let client: ClanTabClient
    private let knownGroups: KnownGroupsStoring
    private let onboarding: OnboardingStoring
    @State private var auth: AuthViewModel
    @AppStorage("clantab.theme") private var theme = AppTheme.system

    init() {
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        let knownGroups = UserDefaultsKnownGroupsStore()
        self.client = client
        self.knownGroups = knownGroups
        self.onboarding = UserDefaultsOnboardingStore()
        _auth = State(initialValue: AuthViewModel(
            client: client,
            sessionStore: KeychainSessionStore(),
            knownGroups: knownGroups,
            syncNudge: UserDefaultsSyncNudgeStore(),
            backupNudge: UserDefaultsBackupNudgeStore()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, knownGroups: knownGroups, auth: auth, onboarding: onboarding)
                .preferredColorScheme(theme.colorScheme)
                .task { appDelegate.authViewModel = auth }
        }
    }
}
