import SwiftUI
import SquareKit

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
            return "\(name(for: expense.payerId)) paid for \(expense.description)"
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

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }
}

struct ActivityRow: View {
    let item: ActivityItem
    let currency: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                Text(item.date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(MoneyFormat.string(minorUnits: item.amountMinor, currency: currency))
        }
    }
}
