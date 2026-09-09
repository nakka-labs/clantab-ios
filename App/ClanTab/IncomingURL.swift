import Foundation

/// The one entry point for every URL that opens the app — a `clantab://g/:id`
/// custom-scheme link or a tapped Universal Link at `AppConfig.shareLinkBaseURL`
/// (`CHECKLIST.md` "Custom domain + Universal Links"). `SceneDelegate` funnels
/// all of them (cold launch and warm, both link types) through here rather than
/// relying on SwiftUI's `.onOpenURL`, which a custom `UISceneDelegate`
/// suppresses. Mirrors `QuickActions`' buffer/notify split exactly.
enum IncomingURL {
    /// A link that arrived before `RootView` could listen (a cold launch) —
    /// it reads this in its `.task`.
    @MainActor private(set) static var pending: URL?

    /// Route an incoming URL: buffer it and post `.urlOpened` for a `RootView`
    /// that's already listening.
    @MainActor
    static func handle(_ url: URL) {
        pending = url
        NotificationCenter.default.post(name: .urlOpened, object: nil, userInfo: ["url": url])
    }

    /// Hand over (and clear) any buffered link, so it routes once.
    @MainActor
    static func consumePending() -> URL? {
        defer { pending = nil }
        return pending
    }
}
