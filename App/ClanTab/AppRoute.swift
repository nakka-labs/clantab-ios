import Foundation

/// Root navigation state. There's no tab bar or deep hierarchy in v1 — the app
/// is either showing the start chooser, one of the two onboarding forms, or the
/// single active group.
enum AppRoute: Equatable {
    case start
    case createGroup
    /// `groupId` is already known when arriving via a deep link to a group the
    /// user hasn't joined yet; `nil` when the user is about to type a join code.
    case joinGroup(groupId: String?)
    /// A signed-in user opened an invite link for a group they hold no membership
    /// in — offer "This is me" (claim) vs "Join as a guest" (`ACCOUNTS_DESIGN.md` §6).
    case chooseJoin(groupId: String)
    /// The "This is me" branch of `chooseJoin`: pick which placeholder member you are.
    case claimMember(groupId: String)
    case group(groupId: String)
}
