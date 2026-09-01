import SwiftUI
import ClanTabKit

/// Picks an `ExpenseCategory` for an expense: one tap for a default, or a custom
/// name + an SF Symbol from the grid. Pushed from `AddExpenseView`; writes the
/// selection back through the binding and pops.
struct CategoryPickerView: View {
    @Binding var selection: ExpenseCategory
    @Environment(\.dismiss) private var dismiss

    @State private var customName: String = ""
    @State private var customIcon: String = ExpenseCategory.iconChoices.first ?? "tag"

    private let iconColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        Form {
            Section {
                row(for: .uncategorized)
                ForEach(ExpenseCategory.defaults, id: \.self) { category in
                    row(for: category)
                }
            }

            Section("Custom") {
                TextField("Category name", text: $customName)

                LazyVGrid(columns: iconColumns, spacing: 12) {
                    ForEach(ExpenseCategory.iconChoices, id: \.self) { icon in
                        Image(systemName: icon)
                            .font(.title3)
                            .frame(width: 44, height: 44)
                            .background(
                                customIcon == icon ? Color.accentColor.opacity(0.2) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(customIcon == icon ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { customIcon = icon }
                            .accessibilityLabel(icon)
                            .accessibilityAddTraits(customIcon == icon ? [.isSelected] : [])
                    }
                }
                .padding(.vertical, 4)

                Button("Use Custom Category") {
                    let trimmed = customName.trimmingCharacters(in: .whitespaces)
                    selection = ExpenseCategory(name: trimmed, symbolName: customIcon)
                    dismiss()
                }
                .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for category: ExpenseCategory) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack {
                Label(category.name, systemImage: category.symbolName)
                Spacer()
                if selection == category {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
        }
        .tint(.primary)
    }
}
