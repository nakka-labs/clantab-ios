import UIKit

/// Exists only to receive Home Screen quick actions (`CHECKLIST.md` "Home
/// Screen quick action"). SwiftUI's `App` lifecycle routes scene events to an
/// internal scene delegate, so `UIApplicationDelegate.application(_:
/// performActionFor:)` is never called — a real `UIWindowSceneDelegate` is
/// the only way to see them. Everything else stays on `ClanTabApp` / the
/// SwiftUI scene; this class does nothing but forward the shortcut.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch via a quick action — buffered until `RootView` reads it.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.handle(item)
        }
    }

    /// Quick action while the app was already backgrounded (the common case).
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActions.handle(shortcutItem))
    }
}
