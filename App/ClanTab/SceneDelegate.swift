import UIKit

/// A real `UIWindowSceneDelegate` — the only way, under SwiftUI's `App`
/// lifecycle, to see Home Screen quick actions (`CHECKLIST.md` "Home Screen
/// quick action") and, because providing this delegate suppresses SwiftUI's
/// own `.onOpenURL`, incoming URLs too (`CHECKLIST.md` "Custom domain +
/// Universal Links"). Every URL — a `clantab://` scheme link or a tapped
/// Universal Link — is funnelled through `IncomingURL`; everything else stays
/// on `ClanTabApp` / the SwiftUI scene.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// Cold launch: a quick action, or a link that opened the app, buffered
    /// until `RootView` reads it.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            QuickActions.handle(item)
        }
        if let url = connectionOptions.urlContexts.first?.url {
            IncomingURL.handle(url)
        } else if let webURL = connectionOptions.userActivities
            .first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb })?.webpageURL {
            IncomingURL.handle(webURL)
        }
    }

    /// Warm open via a `clantab://` custom-scheme link.
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            IncomingURL.handle(url)
        }
    }

    /// Warm open via a tapped Universal Link (`https://clantab.nakka.dev/g/…`).
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return }
        IncomingURL.handle(url)
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
