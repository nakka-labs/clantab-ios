import SwiftUI
import ClanTabKit

/// Every split type, one tap away from `AddExpenseView`'s primary 3-way
/// segmented control (`CHECKLIST.md` UX audit [15]) — Equally/Exact/%
/// cover the overwhelming common case there; this sheet is where Shares and
/// Items live, plus a way back to a common type once you're on one of them
/// (so "Change" from a Shares/Items expense isn't a dead end).
struct MoreSplitsSheet: View {
    let current: SplitType
    let onPicked: (SplitType) -> Void

    @Environment(\.dismiss) private var dismiss

    private static let commonTypes: [SplitType] = [.equal, .exact, .percentage]
    private static let moreTypes: [SplitType] = [.shares, .itemized]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Self.moreTypes, id: \.self) { type in row(type) }
                }
                Section("Common") {
                    ForEach(Self.commonTypes, id: \.self) { type in row(type) }
                }
            }
            .navigationTitle("Split Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func row(_ type: SplitType) -> some View {
        Button {
            onPicked(type)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.fullLabel).foregroundStyle(.primary)
                    Text(type.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if type == current {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
