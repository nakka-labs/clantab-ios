import SwiftUI

/// One row a shareable `RecapCard` could include — just enough to show a
/// checkbox list, independent of whatever domain type (`SimplifiedSettlement`,
/// `MemberSpend`, `Balance`) it was built from at the call site.
struct ShareCardRow: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
}

/// Lets someone pick which rows a share card includes (`CHECKLIST.md` R10) —
/// every `RecapCard`-producing screen (`SettleUpView`, `InsightsView`,
/// `GroupHomeView`'s balances card) used to render every row unconditionally,
/// with no way to share just "what Priya owes" instead of the whole group's
/// business. One shared picker, since all three feed `RecapCard` the same
/// shape of row list already — each call site maps its own typed array to
/// `[ShareCardRow]`, gets a `Set<String>` of selected ids back, and filters
/// its original array by that before building `RecapCard.Content`.
struct ShareCardRowPicker: View {
    let rows: [ShareCardRow]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                ForEach(rows) { row in
                    Button {
                        toggle(row.id)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.title)
                                Text(row.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection.contains(row.id) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .tint(.primary)
                }
            } footer: {
                Text("Choose what to include in the shared card. Everything's included by default.")
            }
        }
        .navigationTitle("Customize Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func toggle(_ id: String) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }
}
