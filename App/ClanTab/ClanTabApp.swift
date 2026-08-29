import SwiftUI
import ClanTabKit

@main
struct ClanTabApp: App {
    private let client = ClanTabClient(baseURL: AppConfig.apiBaseURL)
    private let identityStore: IdentityStoring = UserDefaultsIdentityStore()

    var body: some Scene {
        WindowGroup {
            RootView(client: client, identityStore: identityStore)
        }
    }
}
