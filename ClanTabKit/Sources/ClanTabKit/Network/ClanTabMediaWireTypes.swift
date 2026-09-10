import Foundation

// Wire DTOs for image storage (`CHECKLIST.md` "Image storage backend (R2)" +
// "Profile photos"). `POST /api/media/presign` returns a short-lived presigned
// S3 URL; the client uploads/downloads the bytes directly to R2, the Worker
// never proxies them. All Bearer-gated.

/// What an upload is for — decides the server-derived object key. The client
/// never sends or chooses the key itself.
public enum MediaPurpose: String, Sendable, Codable {
    case avatar
    case groupCover
    case receipt
}

/// `POST /api/media/presign` body. `operation` picks the arm:
/// - `.upload` needs `purpose`, `contentType`, `contentLength` (+ `groupId` for
///   `groupCover`/`receipt`, `expenseId` for `receipt`).
/// - `.view` needs `key`.
public struct MediaPresignRequest: Encodable, Sendable {
    public enum Operation: String, Encodable, Sendable {
        case upload
        case view
    }

    public let operation: Operation
    public let purpose: MediaPurpose?
    public let groupId: String?
    public let expenseId: String?
    public let key: String?
    public let contentType: String?
    public let contentLength: Int?

    public static func upload(
        _ purpose: MediaPurpose,
        contentType: String,
        contentLength: Int,
        groupId: String? = nil,
        expenseId: String? = nil
    ) -> MediaPresignRequest {
        MediaPresignRequest(
            operation: .upload, purpose: purpose, groupId: groupId, expenseId: expenseId,
            key: nil, contentType: contentType, contentLength: contentLength
        )
    }

    public static func view(key: String) -> MediaPresignRequest {
        MediaPresignRequest(
            operation: .view, purpose: nil, groupId: nil, expenseId: nil,
            key: key, contentType: nil, contentLength: nil
        )
    }

    private enum CodingKeys: String, CodingKey {
        case operation, purpose, groupId, expenseId, key, contentType, contentLength
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(operation, forKey: .operation)
        try c.encodeIfPresent(purpose, forKey: .purpose)
        try c.encodeIfPresent(groupId, forKey: .groupId)
        try c.encodeIfPresent(expenseId, forKey: .expenseId)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(contentType, forKey: .contentType)
        try c.encodeIfPresent(contentLength, forKey: .contentLength)
    }
}

/// `operation: "upload"` response — a `PUT` URL plus the exact headers to send
/// with it (they're signed into the URL; deviating gets a 403 from R2).
public struct MediaUploadTicket: Decodable, Sendable {
    public let url: URL
    public let key: String
    public let headers: [String: String]

    public init(url: URL, key: String, headers: [String: String]) {
        self.url = url
        self.key = key
        self.headers = headers
    }
}

/// `operation: "view"` response — a `GET` URL for an existing object.
public struct MediaViewURL: Decodable, Sendable {
    public let url: URL
    public let key: String

    public init(url: URL, key: String) {
        self.url = url
        self.key = key
    }
}

/// `GET /api/auth/avatar` — the signed-in identity's own profile-photo key, or
/// `nil` if it has none. For rendering "my photo" in Settings on a cold launch.
public struct MyAvatarResponse: Decodable, Sendable {
    public let key: String?

    public init(key: String?) {
        self.key = key
    }
}
