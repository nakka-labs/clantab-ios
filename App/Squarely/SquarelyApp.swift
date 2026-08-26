import SwiftUI
import SquareKit

@main
struct SquarelyApp: App {
    private let client = SquarelyClient(baseURL: AppConfig.apiBaseURL)
    private let identityStore: IdentityStoring = UserDefaultsIdentityStore()

    var body: some Scene {
        WindowGroup {
            RootView(client: client, identityStore: identityStore)
        }
    }
}
