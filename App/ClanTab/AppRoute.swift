import Foundation

/// Root navigation state. There's no tab bar or deep hierarchy in v1 — the app
/// is either showing the start chooser, one of the two onboarding forms, or the
/// single active group. Every route past `.start` requires a signed-in session
/// (`MANDATORY_LOGIN_PLAN.md` Part 3) — there's no guest tier anymore.
enum AppRoute: Equatable {
    case start
    case createGroup
    /// "Join with a Code": type a 6-character code, resolved to a `groupId`,
    /// then hands off to `.claimMember`.
    case joinGroup
    /// No membership yet in this group — arrived via a deep link or a resolved
    /// join code: pick which placeholder member is you, or add yourself as a
    /// new member (`ACCOUNTS_DESIGN.md` §6, `MANDATORY_LOGIN_PLAN.md` Part 3).
    case claimMember(groupId: String)
    case group(groupId: String)
}
