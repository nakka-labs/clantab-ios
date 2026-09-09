import ClanTabKit
import SwiftUI

/// The reusable "Your Groups" list (`NAV_POLISH_PLAN.md` Part 1) — the start
/// screen's own inline list, and, from Group Home, a "Switch Group" sheet.
/// Same shape either way: tap a group to open it, context-menu to forget it
/// from this device.
struct GroupsListView: View {
    let groups: [KnownGroup]
    let onOpenGroup: (_ groupId: String) -> Void
    let onRemoveGroup: (_ groupId: String) -> Void
    /// The section caption; `nil` drops it (e.g. inside the "Archived"
    /// disclosure, which has its own label).
    var caption: String? = "YOUR GROUPS"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
            }

            ForEach(groups) { group in
                Button {
                    onOpenGroup(group.groupId)
                } label: {
                    HStack(spacing: 12) {
                        groupBadge(for: group)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name.isEmpty ? "Group" : group.name)
                                .foregroundStyle(.primary)
                            if let balanceLine = Self.balanceLine(for: group) {
                                Text(balanceLine)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Remove from This Device", systemImage: "minus.circle", role: .destructive) {
                        onRemoveGroup(group.groupId)
                    }
                }

                if group.id != groups.last?.id {
                    Divider()
                }
            }
        }
        .padding(.horizontal, 4)
    }

    /// The group's identity badge: its chosen emoji on a light circle of its
    /// formula accent, or — with no emoji — the group's initial in white on a
    /// solid disc of that accent (the same shape as a `MemberAvatar`).
    @ViewBuilder
    private func groupBadge(for group: KnownGroup) -> some View {
        if let emoji = group.emoji, !emoji.isEmpty {
            Text(emoji)
                .font(.body)
                .frame(width: 32, height: 32)
                .background(GroupColor.color(forId: group.groupId).opacity(0.18), in: Circle())
        } else {
            Text(Self.initial(for: group))
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(GroupColor.badge(forId: group.groupId), in: Circle())
        }
    }

    /// One uppercased letter for the badge — the first letter of the group's
    /// name, `"#"` when it has none yet.
    static func initial(for group: KnownGroup) -> String {
        group.name.first(where: \.isLetter).map { String($0).uppercased() } ?? "#"
    }

    /// "You owe ₹500" / "You're owed ₹200" / "Settled up" — `nil` (no line
    /// at all) only while `myBalances` hasn't loaded once yet, distinct
    /// from a confirmed-empty `[]` (`KnownGroup.myBalances`'s doc comment).
    static func balanceLine(for group: KnownGroup) -> String? {
        guard let balances = group.myBalances else { return nil }
        guard let headline = Balances.headline(balances) else { return "Settled up" }
        let amount = MoneyFormat.string(minorUnits: abs(headline.netMinor), currency: headline.currency)
        return headline.netMinor < 0 ? "You owe \(amount)" : "You're owed \(amount)"
    }
}
