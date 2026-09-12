import Foundation

/// A destination pushed onto the Home tab's `NavigationStack`
/// (`RootView.homeStack`, `CHECKLIST.md` UX audit [6]). The app root is a
/// persistent 4-tab bar (`MainTabView`) — Home/Friends/Insights/Settings —
/// not a single-stack switch anymore; these are only the things that still
/// push/pop below the Home tab's root (`StartView`).
enum AppRoute: Hashable {
    case createGroup
    /// "Join with a Code": type a 6-character code, resolved to a `groupId`,
    /// then hands off to `.claimMember`.
    case joinGroup
    /// No membership yet in this group — arrived via a deep link or a resolved
    /// join code: pick which placeholder member is you, or add yourself as a
    /// new member (`ACCOUNTS_DESIGN.md` §6, `MANDATORY_LOGIN_PLAN.md` Part 3).
    /// `accessToken` (`ACCESS_TOKEN_PLAN.md`) rides along from wherever this
    /// route was reached from — the link, the resolved code, or `nil` for a
    /// group that predates the feature.
    case claimMember(groupId: String, accessToken: String?)
    case group(groupId: String)
}
