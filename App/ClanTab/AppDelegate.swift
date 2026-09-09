import UIKit
import UserNotifications
import ClanTabKit

extension Notification.Name {
    /// Posted by `AppDelegate` when the user taps a push notification
    /// (`FEATURE_BACKLOG.md` "Push notifications") — carries the target
    /// group's deep link URL in `userInfo["url"]`, handled identically to any
    /// other incoming URL (`RootView.handleDeepLink`, `.onOpenURL`).
    static let pushNotificationTapped = Notification.Name("clantab.pushNotificationTapped")

    /// Posted when the Home Screen "Add Expense" quick action fires
    /// (`CHECKLIST.md`) — carries the target group id in `userInfo["groupId"]`.
    /// A cold launch buffers it instead (`AppDelegate.consumePendingQuickAction`).
    static let quickActionAddExpense = Notification.Name("clantab.quickActionAddExpense")

    /// Posted by `SceneDelegate` for every incoming URL — a `clantab://` custom
    /// scheme link or a tapped Universal Link (`CHECKLIST.md` "Custom domain +
    /// Universal Links") — carrying it in `userInfo["url"]`. A cold launch
    /// buffers it instead (`IncomingURL.consumePending`). Replaces SwiftUI's
    /// `.onOpenURL`, which a custom `UISceneDelegate` suppresses.
    static let urlOpened = Notification.Name("clantab.urlOpened")
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

    /// The local dashboard balance cache — set once from `ClanTabApp` at
    /// startup, before any push can arrive. `KnownGroupsStoring` is `Sendable`
    /// and lock-guarded, so the push delegate methods (some `nonisolated`,
    /// called on whatever thread APNs uses) can write through it safely
    /// (`CHECKLIST.md` "iOS: push handler writes the carried balance").
    nonisolated(unsafe) var knownGroups: (any KnownGroupsStoring)?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Attach `SceneDelegate` — the only place Home Screen quick actions can
    /// be received under SwiftUI's `App` lifecycle (`CHECKLIST.md`).
    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        config.delegateClass = SceneDelegate.self
        return config
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

    /// Woken (budget permitting) when a push arrives while the app is
    /// backgrounded or suspended — the worker sends a combined
    /// alert + `content-available` payload (`lib/apns.ts`). Folds the
    /// carried balance into the local cache so the dashboard is current
    /// on next open without a fetch; navigation still waits for a tap.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        let applied = applyCarriedBalance(from: userInfo)
        completionHandler(applied ? .newData : .noData)
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show the banner + sound even while the app is in the foreground —
    /// otherwise a push that arrives while the app's open is silently
    /// swallowed instead of shown. Also the foreground path for folding the
    /// carried balance into the cache. `nonisolated` because the protocol
    /// requirement itself isn't main-actor-isolated, and its parameter types
    /// (`UNNotification` etc.) aren't `Sendable` — inheriting this type's
    /// otherwise-default main-actor isolation here would conflict.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        _ = applyCarriedBalance(from: notification.request.content.userInfo)
        return [.banner, .sound]
    }

    /// A tap opens the group the push was about — routed through the same
    /// deep-link path as any other incoming URL, rather than a bespoke
    /// navigation mechanism. `nonisolated` — see `willPresent` above.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        _ = applyCarriedBalance(from: userInfo)
        guard let groupId = userInfo["groupId"] as? String else { return }
        NotificationCenter.default.post(
            name: .pushNotificationTapped,
            object: nil,
            userInfo: ["url": AppConfig.groupShareURL(groupId: groupId)]
        )
    }

    /// Fold a push's carried balance (`balanceCurrency` / `balanceNetMinor`,
    /// set per-recipient by the worker's `notifyGroup`) into the local
    /// dashboard cache — on *receipt*, foreground or background, not only on
    /// tap. Merges into the group's cached `myBalances` so a multi-currency
    /// member's other buckets survive. Returns whether anything was written
    /// (`false` = no balance in the payload, or an unknown group). Safe off
    /// the main actor — `knownGroups` is `Sendable` and lock-guarded.
    /// Internal, not `private`, only so `AppDelegateTests` can drive it.
    @discardableResult
    nonisolated func applyCarriedBalance(from userInfo: [AnyHashable: Any]) -> Bool {
        guard let store = knownGroups,
              let groupId = userInfo["groupId"] as? String,
              let currency = userInfo["balanceCurrency"] as? String,
              let netString = userInfo["balanceNetMinor"] as? String,
              let netMinor = Int64(netString),
              let group = store.all().first(where: { $0.groupId == groupId })
        else { return false }
        let merged = Balances.applyingCarriedBalance(
            to: group.myBalances ?? [],
            memberId: group.myBalances?.first?.memberId ?? "",
            currency: currency,
            netMinor: netMinor
        )
        store.updateBalances(groupId: groupId, myBalances: merged)
        return true
    }
}
