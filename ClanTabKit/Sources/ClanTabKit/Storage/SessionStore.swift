import Foundation

/// A signed-in identity's session (`ACCOUNTS_DESIGN.md` §3): our own HMAC-signed
/// token plus the bits the app needs to manage it. Stored in the Keychain on
/// device — never `UserDefaults`.
public struct StoredSession: Codable, Sendable, Equatable {
    /// Which identity provider minted this session (`MANDATORY_LOGIN_PLAN.md`
    /// Part 1) — Apple and Google need different launch-time handling below.
    public enum Provider: String, Codable, Sendable, Equatable {
        case apple
        case google
    }

    /// The session JWT. Sent as `Authorization: Bearer <token>` on identity
    /// endpoints; verified server-side with no DO round-trip.
    public let token: String
    public let provider: Provider
    /// Apple's stable, app-scoped user id (`ASAuthorizationAppleIDCredential.user`),
    /// present only when `provider == .apple`. Needed for the
    /// `getCredentialState(forUserID:)` launch check that lets "revoke in iOS
    /// Settings" end the session with no server plumbing. Google has no
    /// equivalent client-side revocation check — a Google session relies on
    /// token expiry alone.
    public let appleUserID: String?
    /// When `token` stops verifying. The server enforces this too — it's here so
    /// the app can refresh ahead of time.
    public let expiresAt: Date

    public init(token: String, provider: Provider, appleUserID: String? = nil, expiresAt: Date) {
        self.token = token
        self.provider = provider
        self.appleUserID = appleUserID
        self.expiresAt = expiresAt
    }

    /// Past `expiresAt` — the token will be rejected; drop back to guest mode.
    public func isExpired(now: Date = Date()) -> Bool {
        expiresAt <= now
    }

    /// Within `window` of expiry (default 7 days) — time to call
    /// `refreshSession` on launch (§3).
    public func needsRefresh(within window: TimeInterval = 7 * 24 * 60 * 60, now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) < window
    }
}

/// Abstracts session persistence so ClanTabKit's callers don't depend on the
/// Keychain directly. The app supplies `KeychainSessionStore`; tests and
/// previews use `InMemorySessionStore`.
public protocol SessionStoring: Sendable {
    func load() -> StoredSession?
    func save(_ session: StoredSession)
    func clear()
}

/// In-memory session store for tests and SwiftUI previews — never persists.
public final class InMemorySessionStore: SessionStoring, @unchecked Sendable {
    private var session: StoredSession?
    private let lock = NSLock()

    public init(_ session: StoredSession? = nil) {
        self.session = session
    }

    public func load() -> StoredSession? {
        lock.lock(); defer { lock.unlock() }
        return session
    }

    public func save(_ session: StoredSession) {
        lock.lock(); defer { lock.unlock() }
        self.session = session
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        session = nil
    }
}

#if canImport(Security)
import Security

/// Keychain-backed session store — one `kSecClassGenericPassword` item,
/// `kSecAttrAccessibleAfterFirstUnlock` so the launch-time refresh can read it
/// before the user unlocks the device (`ACCOUNTS_DESIGN.md` §3).
public final class KeychainSessionStore: SessionStoring, @unchecked Sendable {
    private let service: String
    private let account = "session"
    private let lock = NSLock()

    public init(service: String = "com.clantab.app.session") {
        self.service = service
    }

    public func load() -> StoredSession? {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredSession.self, from: data)
    }

    public func save(_ session: StoredSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        lock.lock(); defer { lock.unlock() }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insert = baseQuery()
            insert.merge(attributes) { _, new in new }
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    public func clear() {
        lock.lock(); defer { lock.unlock() }
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
