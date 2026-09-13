import SwiftUI
import ClanTabKit

/// A read-only detail screen for one activity-feed row (`CHECKLIST.md` R8) —
/// tapping a row used to jump straight into editing, with no way to just
/// *look* first; a mis-tap started an edit session on someone's expense with
/// no warning. This is the new tap destination; "Edit" is now an explicit,
/// deliberate second step, matching how this app already treats everything
/// else (view first, edit is separate) — `AddExpenseView`/`EditSettlementView`
/// stay the actual edit sheets, opened only from the toolbar button here.
struct ActivityDetailView: View {
    let item: ActivityItem
    let members: [Member]
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    let onEdit: () -> Void

    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    private var amount: String {
        MoneyFormat.string(minorUnits: item.amountMinor, currency: item.currency)
    }

    var body: some View {
        List {
            headerSection
            switch item.kind {
            case .expense(let expense):
                payersSection(expense)
                splitSection(expense)
                if let attachments = expense.attachments, !attachments.isEmpty {
                    receiptsSection(attachments)
                }
                commentsSection(expense)
            case .settlement(let settlement):
                settlementSection(settlement)
            }
        }
        .navigationTitle(item.category != nil ? "Expense" : "Settlement")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit", action: onEdit)
            }
        }
        .task {
            guard case .expense(let expense) = item.kind else { return }
            isLoadingComments = true
            defer { isLoadingComments = false }
            comments = (try? await client.listComments(groupId: groupId, expenseId: expense.id, accessToken: accessToken))?
                .comments ?? []
        }
    }

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                if let category = item.category {
                    CategoryIconBadge(category: category, size: 44)
                } else {
                    MemberAvatar(name: item.actorName, size: 44)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.headline)
                    Text(item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 4)
            Text(amount).font(.largeTitle.weight(.semibold))
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Expense

    private func payersSection(_ expense: Expense) -> some View {
        Section(expense.payers.count > 1 ? "Paid by" : "Paid by \(name(for: expense.payers[0].memberId))") {
            if expense.payers.count > 1 {
                ForEach(expense.payers, id: \.memberId) { payer in
                    HStack {
                        Text(name(for: payer.memberId))
                        Spacer()
                        Text(MoneyFormat.string(minorUnits: payer.amountMinor, currency: expense.currency))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let categoryName = item.categoryName {
                HStack {
                    Text("Category")
                    Spacer()
                    Text(categoryName).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func splitSection(_ expense: Expense) -> some View {
        Section("Split \(expense.splitType.shortLabel)") {
            ForEach(expense.splits, id: \.memberId) { split in
                HStack {
                    Text(name(for: split.memberId))
                    Spacer()
                    Text(MoneyFormat.string(minorUnits: split.amountMinor, currency: expense.currency))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func receiptsSection(_ attachments: [String]) -> some View {
        Section("Receipts") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(attachments, id: \.self) { key in
                        ReceiptThumbnail(key: key, accessToken: accessToken)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func commentsSection(_ expense: Expense) -> some View {
        if isLoadingComments {
            Section("Comments") {
                ProgressView()
            }
        } else if !comments.isEmpty {
            Section("Comments") {
                ForEach(comments) { comment in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name(for: comment.authorMemberId)).font(.subheadline.weight(.medium))
                        Text(comment.text)
                        Text(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    // MARK: - Settlement

    private func settlementSection(_ settlement: Settlement) -> some View {
        Section {
            HStack {
                Text("From")
                Spacer()
                Text(name(for: settlement.fromId)).foregroundStyle(.secondary)
            }
            HStack {
                Text("To")
                Spacer()
                Text(name(for: settlement.toId)).foregroundStyle(.secondary)
            }
        }
    }
}
