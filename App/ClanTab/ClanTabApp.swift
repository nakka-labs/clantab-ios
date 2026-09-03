import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    private let client: ClanTabClient
    private let identityStore: IdentityStoring
    private let knownGroups: KnownGroupsStoring
    @State private var auth: AuthViewModel

    init() {
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        let identityStore = UserDefaultsIdentityStore()
        let knownGroups = UserDefaultsKnownGroupsStore()
        self.client = client
        self.identityStore = identityStore
        self.knownGroups = knownGroups
        _auth = State(initialValue: AuthViewModel(
            client: client,
            sessionStore: KeychainSessionStore(),
            identityStore: identityStore,
            knownGroups: knownGroups
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, identityStore: identityStore, knownGroups: knownGroups, auth: auth)
        }
    }
}
