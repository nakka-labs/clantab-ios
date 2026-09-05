import UIKit
import UserNotifications
import ClanTabKit

extension Notification.Name {
    /// Posted by `AppDelegate` when the user taps a push notification
    /// (`FEATURE_BACKLOG.md` "Push notifications") — carries the target
    /// group's deep link URL in `userInfo["url"]`, handled identically to any
    /// other incoming URL (`RootView.handleDeepLink`, `.onOpenURL`).
    static let pushNotificationTapped = Notification.Name("clantab.pushNotificationTapped")
}

/// Bridges the UIKit-only push-notification APIs into the SwiftUI app —
/// `UIApplication`'s registration callbacks and `UNUserNotificationCenterDelegate`
/// have no SwiftUI-native equivalent (`FEATURE_BACKLOG.md` "Push
/// notifications"). Deliberately an App-target type, never `ClanTabKit` — the
/// cross-platform guardrail in `AGENTS.md` keeps Apple-only frameworks out of
/// the shared package.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set from `ClanTabApp` once its own state exists. A device token that
    /// arrives before then (registration can complete before SwiftUI's first
    /// render) is buffered in `pendingDeviceToken` and flushed as soon as
    /// this is set.
    var authViewModel: AuthViewModel? {
        didSet { flushPendingDeviceToken() }
    }
    private var pendingDeviceToken: String?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        pendingDeviceToken = deviceToken.map { String(format: "%02x", $0) }.joined()
        flushPendingDeviceToken()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Expected on the Simulator (no real APNs registration is possible
        // there) and on a real device until the Apple Developer portal setup
        // in `NEXT_STEPS.md` Phase 6 is done — never fatal.
        print("Push registration failed: \(error)")
    }

    private func flushPendingDeviceToken() {
        guard let authViewModel, let deviceToken = pendingDeviceToken else { return }
        pendingDeviceToken = nil
        Task { await authViewModel.registerDeviceToken(deviceToken) }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner + sound even while the app is in the foreground —
    /// otherwise a push that arrives while the app's open is silently
    /// swallowed instead of shown. `nonisolated` because the protocol
    /// requirement itself isn't main-actor-isolated, and its parameter types
    /// (`UNNotification` etc.) aren't `Sendable` — inheriting this type's
    /// otherwise-default main-actor isolation here would conflict.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// A tap opens the group the push was about — routed through the same
    /// deep-link path as any other incoming URL, rather than a bespoke
    /// navigation mechanism. `nonisolated` — see `willPresent` above.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let groupId = response.notification.request.content.userInfo["groupId"] as? String else { return }
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: ["url": AppConfig.groupShareURL(groupId: groupId)]
        )
    }
}
