import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    private let client: ClanTabClient
    private let knownGroups: KnownGroupsStoring
    @State private var auth: AuthViewModel

    init() {
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        let knownGroups = UserDefaultsKnownGroupsStore()
        self.client = client
        self.knownGroups = knownGroups
        _auth = State(initialValue: AuthViewModel(
            client: client,
            sessionStore: KeychainSessionStore(),
            knownGroups: knownGroups,
            syncNudge: UserDefaultsSyncNudgeStore()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, knownGroups: knownGroups, auth: auth)
        }
    }
}
