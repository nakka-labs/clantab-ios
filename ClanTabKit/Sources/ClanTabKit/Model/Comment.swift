import Foundation

/// One comment on an expense (`CHECKLIST.md` "Comments on an expense") —
/// fetched separately, per expense, never embedded in `GroupStateResponse`
/// (that response is polled every ~25s; comments aren't, so they stay off it).
/// Soft-deleted like an `Expense`/`Settlement`, but with no restore path — a
/// deleted comment is gone from every list, permanently.
public struct Comment: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let expenseId: String
    public let authorMemberId: String
    public let text: String
    public let createdAt: Date
    public let deletedAt: Date?
    public let deletedBy: String?

    public init(
        id: String,
        expenseId: String,
        authorMemberId: String,
        text: String,
        createdAt: Date,
        deletedAt: Date? = nil,
        deletedBy: String? = nil
    ) {
        self.id = id
        self.expenseId = expenseId
        self.authorMemberId = authorMemberId
        self.text = text
        self.createdAt = createdAt
        self.deletedAt = deletedAt
        self.deletedBy = deletedBy
    }
}
