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
    case group(groupId: String)
}
