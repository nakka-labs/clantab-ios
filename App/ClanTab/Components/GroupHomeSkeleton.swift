import SwiftUI
import ClanTabKit

/// Skeleton rows for Group Home's Members/Activity sections while
/// `GroupViewModel.state` is still loading (`CHECKLIST.md` UX audit [10]) —
/// previously only the balance hero got a placeholder; these two sections
/// were simply absent until the first load finished, so a slow connection
/// showed a lone hero card floating over blank space.
enum GroupHomeSkeleton {
    /// Reuses the real `MemberBalanceRow` over placeholder data rather than
    /// inventing a parallel row shape — guaranteed to stay visually in sync
    /// with the real row, and `MemberBalanceRow` doesn't care whether its
    /// `Member`/`Balance` correspond to anything real.
    static func memberRows(count: Int = 3) -> some View {
        ForEach(0..<count, id: \.self) { index in
            MemberBalanceRow(
                member: Member(id: "skeleton-\(index)", displayName: "Loading Name"),
                balances: [Balance(memberId: "skeleton-\(index)", currency: "INR", netMinor: 100_000)]
            )
        }
        .redacted(reason: .placeholder)
    }

    /// A generic row matching `ActivityRow`'s shape (leading badge, title +
    /// metadata line, trailing amount) rather than reusing it directly —
    /// `ActivityRow` needs a real `Expense`/`Settlement` to build an
    /// `ActivityItem` from, not worth constructing just for a placeholder.
    static func activityRows(count: Int = 3) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            HStack(spacing: 12) {
                Circle().fill(.secondary.opacity(0.2)).frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Loading expense title")
                    Text("Category · Date").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("₹000").lineLimit(1)
            }
        }
        .redacted(reason: .placeholder)
    }
}
