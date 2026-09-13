import SwiftUI
import ClanTabKit

/// One editable line item for an `.itemized` split — the mutable, string-typed
/// counterpart to `ClanTabKit.LineItem`, resolved to exact splits only on
/// save. Lives alongside its editor (`CHECKLIST.md` D5) since nothing outside
/// itemized-split editing ever touches it.
struct ItemDraft: Identifiable {
    let id: String
    var name: String
    var amountText: String
    var participantIds: Set<String>

    init(id: String = UUID().uuidString, name: String = "", amountText: String = "", participantIds: Set<String>) {
        self.id = id
        self.name = name
        self.amountText = amountText
        self.participantIds = participantIds
    }
}

/// Pure math shared between this editor's own row coloring and
/// `AddExpenseView`'s `canSubmit`/`save()` (which need the same total to
/// validate against, but don't otherwise touch the editor UI) — one
/// implementation so the two can never drift (`CHECKLIST.md` D5).
enum ItemizedSplitMath {
    static func itemsOnlyTotal(_ drafts: [ItemDraft]) -> Int64 {
        drafts.reduce(Int64(0)) { $0 + (MoneyFormat.minorUnits(from: $1.amountText) ?? 0) }
    }

    /// Items + tax + tip — what must equal the expense's own amount
    /// (`CHECKLIST.md` "Tax/tip proportional split on itemized expenses"),
    /// not the items alone.
    static func total(_ drafts: [ItemDraft], taxMinor: Int64, tipMinor: Int64) -> Int64 {
        itemsOnlyTotal(drafts) + taxMinor + tipMinor
    }
}

/// The itemized-split editor: line items (name, amount, participants),
/// tax/tip, and the running total vs. the expense's own amount. Extracted
/// out of `AddExpenseView` (`CHECKLIST.md` D5 — 1438 lines doing five jobs).
/// Every binding here is a `@State` `AddExpenseView` already owned before
/// this split, just handed down instead of inlined — a pure move, no
/// behavior change.
struct ItemizedSplitEditor: View {
    @Binding var itemDrafts: [ItemDraft]
    @Binding var taxText: String
    @Binding var tipText: String
    /// Lets "Set amount to X" / "Use X" below write back to the parent's own
    /// amount field.
    @Binding var amountText: String
    let members: [Member]
    let currency: String
    /// The parsed amount field, `nil` while it doesn't fully resolve —
    /// mirrors `AddExpenseView.amountMinor` exactly. Passed in rather than
    /// recomputed here: parsing the expression (`MoneyFormat.evaluate`) is
    /// the parent's own concern, not this editor's.
    let amountMinor: Int64?
    /// Shared with `AddExpenseView`'s exact-split and multi-payer rows —
    /// passed in rather than duplicated so all three keep identical wording.
    let remainingLabel: (Int64) -> String

    private var itemsOnlyTotal: Int64 { ItemizedSplitMath.itemsOnlyTotal(itemDrafts) }
    private var taxMinorValue: Int64 { MoneyFormat.minorUnits(from: taxText) ?? 0 }
    private var tipMinorValue: Int64 { MoneyFormat.minorUnits(from: tipText) ?? 0 }
    private var itemizedTotal: Int64 { itemsOnlyTotal + taxMinorValue + tipMinorValue }

    /// `true` once the amount is known and the line items don't add up to it.
    private var itemizedMismatch: Bool {
        guard let amountMinor else { return false }
        return amountMinor != itemizedTotal
    }

    var body: some View {
        ForEach($itemDrafts) { $item in
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    TextField("Item", text: $item.name)
                    TextField("0.00", text: $item.amountText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .foregroundStyle(itemizedMismatch && (MoneyFormat.minorUnits(from: item.amountText) ?? 0) > 0 ? Color.red : Color.primary)
                }
                // An inline avatar row, not a `Menu` (`CHECKLIST.md` UX audit
                // [18]) — who's sharing this item is visible at a glance, and
                // toggling one doesn't require opening anything.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(members) { member in
                            let isIncluded = item.participantIds.contains(member.id)
                            Button {
                                if isIncluded {
                                    item.participantIds.remove(member.id)
                                } else {
                                    item.participantIds.insert(member.id)
                                }
                            } label: {
                                MemberAvatar(member, size: 30)
                                    .saturation(isIncluded ? 1 : 0)
                                    .opacity(isIncluded ? 1 : 0.35)
                                    .overlay(alignment: .bottomTrailing) {
                                        if isIncluded {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 13))
                                                .symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, .green)
                                                .background(Circle().fill(.white).padding(1.5))
                                                .offset(x: 2, y: 2)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(member.displayName)
                            .accessibilityAddTraits(isIncluded ? [.isSelected] : [])
                            .accessibilityHint("Double tap to \(isIncluded ? "remove" : "add")")
                        }
                    }
                    .padding(.vertical, 2)
                }
                if item.participantIds.isEmpty {
                    Text("No one — tap someone above to add them")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            // No longer `.accessibilityElement(children: .combine)` — that
            // collapsed the name/amount fields and every avatar toggle into
            // one opaque VoiceOver stop, which would have made the
            // per-member buttons (added for [18] above) unreachable. Each
            // field and avatar is its own stop now, which is also more
            // useful: a VoiceOver user can act on one member at a time
            // instead of getting a single "Line item X" blob.
        }
        .onDelete { itemDrafts.remove(atOffsets: $0) }

        Button {
            itemDrafts.append(ItemDraft(participantIds: Set(members.map(\.id))))
        } label: {
            Label("Add Item", systemImage: "plus.circle")
        }
        .font(.footnote)

        // Tax/tip (`CHECKLIST.md` "Tax/tip proportional split on itemized
        // expenses") — split by each person's own item subtotal at save time
        // (`Validation.itemizedSplit`), not split evenly like the items above.
        HStack(spacing: 8) {
            Text("Tax")
            TextField("0.00", text: $taxText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        HStack(spacing: 8) {
            Text("Tip")
            TextField("0.00", text: $tipText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
        }
        if taxMinorValue > 0 || tipMinorValue > 0 {
            Text("Split by what each person ordered, not evenly.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        if let amountMinor {
            HStack {
                Text(remainingLabel(amountMinor - itemizedTotal))
                    .font(.footnote)
                    .foregroundStyle(amountMinor == itemizedTotal ? Color.secondary : Color.red)
                Spacer()
                if itemizedMismatch, itemizedTotal > 0 {
                    Button("Use \(MoneyFormat.string(minorUnits: itemizedTotal, currency: currency))") {
                        amountText = MoneyFormat.plainString(minorUnits: itemizedTotal)
                    }
                    .font(.footnote)
                }
            }
        } else if itemizedTotal > 0 {
            // No amount typed yet — offer the items' sum as the amount.
            Button("Set amount to \(MoneyFormat.string(minorUnits: itemizedTotal, currency: currency))") {
                amountText = MoneyFormat.plainString(minorUnits: itemizedTotal)
            }
            .font(.footnote)
        }
    }
}
