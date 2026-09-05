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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("YOUR GROUPS")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            ForEach(groups) { group in
                Button {
                    onOpenGroup(group.groupId)
                } label: {
                    HStack {
                        Text(group.name.isEmpty ? "Group" : group.name)
                            .foregroundStyle(.primary)
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
}
