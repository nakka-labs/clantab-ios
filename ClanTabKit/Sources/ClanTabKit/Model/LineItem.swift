import Foundation

/// One line of an itemized expense (`FEATURE_BACKLOG.md` "Itemized expense
/// entry") — a named thing that cost `amountMinor`, shared equally among the
/// members in `participantIds`.
///
/// Itemization is an *input method*, like `percentage`: the client resolves the
/// items into exact per-member `ExpenseSplit`s before dispatch
/// (`Validation.itemizedSplit`), and the server validates those splits sum to
/// the expense amount exactly as it does for every other `splitType`. The items
/// themselves are also stored, so reopening the expense shows the breakdown and
/// an edit starts from it.
///
/// All items of an expense must together sum to that expense's `amountMinor` —
/// there is no separate tax/tip bucket; a shared surcharge is entered as its
/// own line assigned to everyone.
public struct LineItem: Codable, Sendable, Equatable, Identifiable {
    /// Stable per item so an edit can diff rows rather than rebuild them. The
    /// client generates it; the server stores it verbatim (no meaning attached,
    /// same trust model as every other client-supplied id).
    public let id: String
    /// What it was ("Pizza", "Taxi"). May be empty — the amount and the people
    /// are what matter to the split.
    public let name: String
    public let amountMinor: Int64
    /// The members sharing this line, equally. Never empty. Order is preserved
    /// but not meaningful.
    public let participantIds: [String]

    public init(id: String, name: String, amountMinor: Int64, participantIds: [String]) {
        self.id = id
        self.name = name
        self.amountMinor = amountMinor
        self.participantIds = participantIds
    }
}
