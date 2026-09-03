import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    private let client: ClanTabClient
    private let identityStore: IdentityStoring
    @State private var auth: AuthViewModel

    init() {
        let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
        self.client = client
        self.identityStore = UserDefaultsIdentityStore()
        _auth = State(initialValue: AuthViewModel(client: client, sessionStore: KeychainSessionStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView(client: client, identityStore: identityStore, auth: auth)
        }
    }
}
