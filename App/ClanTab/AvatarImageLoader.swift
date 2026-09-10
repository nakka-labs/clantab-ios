import SwiftUI
import ClanTabKit

/// Resolves a `Member.avatarKey` to a `UIImage` for `MemberAvatar`
/// (`CHECKLIST.md` "Profile photos").
///
/// - The key is stable per identity, so a resolved image is memory-cached and
///   reused everywhere that member appears.
/// - A key that 404s or fails is remembered so we don't refetch it on every
///   render — the member just shows `MemberColor` initials.
/// - Concurrent requests for the same key share one network round-trip.
///
/// Injected into the environment at the app root; views without it (previews,
/// tests) fall back to initials.
@MainActor
@Observable
final class AvatarImageLoader {
    @ObservationIgnored private let client: ClanTabClient
    /// Read fresh each fetch so a token refresh / sign-out is picked up.
    @ObservationIgnored private weak var auth: AuthViewModel?

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var failed: Set<String> = []
    @ObservationIgnored private var inFlight: [String: Task<Data?, Never>] = [:]

    /// Bumped whenever a cache entry is replaced or cleared. `MemberAvatar`
    /// folds it into its `.task` id so a photo change (the key is stable, so the
    /// id wouldn't otherwise move) re-resolves every avatar — cached ones from
    /// memory, the changed one from the primed image or a refetch.
    private(set) var generation = 0

    init(client: ClanTabClient, auth: AuthViewModel) {
        self.client = client
        self.auth = auth
        cache.countLimit = 200
    }

    private var sessionToken: String? { auth?.session?.token }

    /// A already-resolved image for `key`, without hitting the network — for a
    /// synchronous first paint before `load(_:)`'s `await` returns.
    func cached(_ key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    /// The image for `key`: cache hit, or a presign + download. `nil` on any
    /// failure (no session, 404, decode) — the caller shows initials.
    func load(_ key: String) async -> UIImage? {
        if let hit = cache.object(forKey: key as NSString) { return hit }
        if failed.contains(key) { return nil }

        let data = await fetchData(key)
        guard let data, let image = UIImage(data: data) else {
            failed.insert(key)
            return nil
        }
        cache.setObject(image, forKey: key as NSString)
        return image
    }

    private func fetchData(_ key: String) async -> Data? {
        if let existing = inFlight[key] { return await existing.value }
        guard let token = sessionToken else { return nil }

        let client = self.client
        let task = Task<Data?, Never> {
            do {
                let view = try await client.presignMediaView(key: key, token: token)
                let (data, response) = try await URLSession.shared.data(from: view.url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                return data
            } catch {
                return nil
            }
        }
        inFlight[key] = task
        let result = await task.value
        inFlight[key] = nil
        return result
    }

    /// Forget one key's cached/failed state so the next `load` refetches — call
    /// after the current user removes their own photo.
    func invalidate(_ key: String) {
        cache.removeObject(forKey: key as NSString)
        failed.remove(key)
        generation += 1
    }

    /// Seed the cache with an image we already have in hand (the photo the user
    /// just picked), so it shows instantly without a round-trip.
    func prime(_ key: String, with image: UIImage) {
        cache.setObject(image, forKey: key as NSString)
        failed.remove(key)
        generation += 1
    }

    /// Drop everything — on sign-out / account switch, so a new identity never
    /// sees the previous one's photos.
    func clearAll() {
        cache.removeAllObjects()
        failed.removeAll()
        for task in inFlight.values { task.cancel() }
        inFlight.removeAll()
        generation += 1
    }
}

private struct AvatarImageLoaderKey: EnvironmentKey {
    static let defaultValue: AvatarImageLoader? = nil
}

extension EnvironmentValues {
    var avatarImageLoader: AvatarImageLoader? {
        get { self[AvatarImageLoaderKey.self] }
        set { self[AvatarImageLoaderKey.self] = newValue }
    }
}
