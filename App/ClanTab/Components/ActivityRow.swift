import SwiftUI
import ClanTabKit

/// A single row in the Group Home activity feed — either an expense or a
/// settlement, normalized to one shape so the two can be merged and sorted by
/// date together.
struct ActivityItem: Identifiable {
    enum Kind {
        case expense(Expense)
        case settlement(Settlement)
    }

    let id: String
    let date: Date
    let kind: Kind
    private let members: [Member]

    init(expense: Expense, members: [Member]) {
        self.id = "expense-\(expense.id)"
        self.date = expense.date
        self.kind = .expense(expense)
        self.members = members
    }

    init(settlement: Settlement, members: [Member]) {
        self.id = "settlement-\(settlement.id)"
        self.date = settlement.date
        self.kind = .settlement(settlement)
        self.members = members
    }

    var title: String {
        switch kind {
        case .expense(let expense):
            return "\(payerSummary(expense.payers)) paid for \(expense.description)"
        case .settlement(let settlement):
            return "\(name(for: settlement.fromId)) paid \(name(for: settlement.toId))"
        }
    }

    var amountMinor: Int64 {
        switch kind {
        case .expense(let expense): return expense.amountMinor
        case .settlement(let settlement): return settlement.amountMinor
        }
    }

    var currency: String {
        switch kind {
        case .expense(let expense): return expense.currency
        case .settlement(let settlement): return settlement.currency
        }
    }

    /// The expense's resolved category, for its pastel badge
    /// (`FEATURE_BACKLOG.md` "Category colors, formula-driven"). `nil` for a
    /// settlement — those keep the neutral gray marker, there's no category.
    var category: ExpenseCategory? {
        switch kind {
        case .expense(let expense):
            return ExpenseCategory.resolve(name: expense.category, symbolName: expense.categoryIcon)
        case .settlement:
            return nil
        }
    }

    /// When this was soft-deleted (`FEATURE_BACKLOG.md` "Recently Deleted") —
    /// `nil` for anything in the normal, active feed.
    var deletedAt: Date? {
        switch kind {
        case .expense(let expense): return expense.deletedAt
        case .settlement(let settlement): return settlement.deletedAt
        }
    }

    /// The person this row leads with — the payer of an expense, the sender
    /// of a settlement — for their identity avatar. Always set (both kinds
    /// have an actor); `"Someone"` if the member is no longer in the group.
    var actorName: String {
        switch kind {
        // The first payer stands in for the avatar on a multi-payer expense
        // (`CHECKLIST.md` "Multiple payers on one expense") — the full
        // "Ana & Ben" phrasing lives in `title`, not the identity glyph.
        case .expense(let expense): return name(for: expense.payers.first?.memberId ?? "")
        case .settlement(let settlement): return name(for: settlement.fromId)
        }
    }

    /// "Ana" (one payer), "Ana & Ben" (two), "Ana & 2 others" (three or more)
    /// (`CHECKLIST.md` "Multiple payers on one expense").
    private func payerSummary(_ payers: [ExpensePayment]) -> String {
        let names = payers.map { name(for: $0.memberId) }
        switch names.count {
        case 0: return "Someone" // shouldn't happen — every expense has ≥1 payer
        case 1, 2: return names.joined(separator: " & ")
        default: return "\(names[0]) & \(names.count - 1) others"
        }
    }

    /// The category label, shown as a caption on expense rows when set.
    var categoryName: String? {
        switch kind {
        case .expense(let expense):
            guard let name = expense.category, !name.isEmpty else { return nil }
            return name
        case .settlement:
            return nil
        }
    }

    /// Whether this expense has a receipt photo attached (`CHECKLIST.md` "Photo
    /// attachment on an expense") — the feed row shows a paperclip.
    var hasAttachments: Bool {
        if case .expense(let expense) = kind { return !(expense.attachments ?? []).isEmpty }
        return false
    }

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var amount: String {
        MoneyFormat.string(minorUnits: item.amountMinor, currency: item.currency)
    }

    var body: some View {
        HStack(spacing: 12) {
            if let category = item.category {
                // An expense leads with its category badge; the payer is
                // named in the row title.
                CategoryIconBadge(category: category)
            } else {
                // A settlement has no category — lead with the sender's
                // identity avatar instead of a nondescript arrow glyph.
                MemberAvatar(name: item.actorName, size: 32)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                metadataLine
                // At accessibility text sizes there's no room for the amount
                // beside the title, so it drops below it rather than wrapping
                // the number character by character.
                if dynamicTypeSize.isAccessibilitySize {
                    Text(amount).font(.headline).lineLimit(1)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
                Text(amount).lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [item.title, item.categoryName, amount]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        .accessibilityValue(item.date.formatted(date: .abbreviated, time: .omitted))
    }

    /// At accessibility text sizes, "category · date" no longer fits one
    /// line — the old `.lineLimit(1)` on the whole row truncated *each*
    /// piece independently ("Shop…", "11 Sep…"), leaving neither readable
    /// (`CHECKLIST.md` "UI audit, fresh eyes pass"). Same fix as the
    /// amount above: drop the separator and stack instead of truncating.
    @ViewBuilder
    private var metadataLine: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 2) {
                if let categoryName = item.categoryName {
                    Text(categoryName)
                }
                HStack(spacing: 4) {
                    Text(item.date, style: .date)
                    if item.hasAttachments {
                        Image(systemName: "paperclip")
                            .accessibilityLabel("Has a receipt")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                if let categoryName = item.categoryName {
                    Text(categoryName)
                    Text("·")
                }
                Text(item.date, style: .date)
                if item.hasAttachments {
                    Image(systemName: "paperclip")
                        .accessibilityLabel("Has a receipt")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
    }
}
