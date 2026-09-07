import UIKit
import ClanTabKit

/// The one Home Screen quick action (`CHECKLIST.md` "Home Screen quick
/// action") — long-press the app icon to "Add Expense" to whichever group
/// you were most recently in. Dynamic, because the subtitle is the group's
/// name; refreshed whenever the known-groups list changes.
enum QuickActions {
    /// `UIApplicationShortcutItem.type` for the add-expense action.
    static let addExpenseType = "com.clantab.quickaction.addExpense"
    /// Key under which the target group id rides in the item's `userInfo`.
    static let groupIdKey = "groupId"

    /// The group a quick-added expense would go to: the most-recently-opened
    /// one that has a name yet (an unopened join/deep-link group has none —
    /// see `KnownGroup.name`). `nil` when there's nothing to offer.
    static func primaryGroup(_ groups: [KnownGroup]) -> KnownGroup? {
        // `KnownGroupsStoring.all()` is already most-recent-first.
        groups.first { !$0.name.isEmpty }
    }

    /// The single dynamic shortcut item for `groups`, or `nil` if there's no
    /// group to point it at.
    static func shortcutItem(_ groups: [KnownGroup]) -> UIApplicationShortcutItem? {
        guard let group = primaryGroup(groups) else { return nil }
        return UIApplicationShortcutItem(
            type: addExpenseType,
            localizedTitle: "Add Expense",
            localizedSubtitle: group.name,
            icon: UIApplicationShortcutIcon(systemImageName: "plus.circle"),
            userInfo: [groupIdKey: group.groupId as NSString]
        )
    }

    /// The target group id carried by a quick-action item, or `nil` if it
    /// isn't ours / carries no id.
    static func targetGroupId(from item: UIApplicationShortcutItem) -> String? {
        guard item.type == addExpenseType else { return nil }
        return item.userInfo?[groupIdKey] as? String
    }

    /// A quick action that fired before `RootView` could listen (a cold
    /// launch) — it reads this in its `.task`.
    @MainActor private(set) static var pendingGroupId: String?

    /// Route a fired quick action: buffer it and post `.quickActionAddExpense`
    /// for a `RootView` that's already listening. Returns whether it was ours.
    @MainActor
    @discardableResult
    static func handle(_ item: UIApplicationShortcutItem) -> Bool {
        guard let groupId = targetGroupId(from: item) else { return false }
        pendingGroupId = groupId
        NotificationCenter.default.post(
            name: .quickActionAddExpense, object: nil, userInfo: [groupIdKey: groupId]
        )
        return true
    }

    /// Hand over (and clear) any buffered quick action, so it fires once.
    @MainActor
    static func consumePending() -> String? {
        defer { pendingGroupId = nil }
        return pendingGroupId
    }

    /// Point the Home Screen quick action at the current primary group (or
    /// clear it). Safe to call often — a no-op when nothing changed.
    @MainActor
    static func refresh(_ groups: [KnownGroup]) {
        let items = shortcutItem(groups).map { [$0] } ?? []
        if UIApplication.shared.shortcutItems != items {
            UIApplication.shared.shortcutItems = items
        }
    }
}
