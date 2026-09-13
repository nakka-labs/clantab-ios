import SwiftUI
import ClanTabKit

/// Renders the server-computed settle-up plan (`DESIGN.md` §2's
/// `simplifiedSettlements` — never recomputed client-side) as minimal
/// transaction cards, each with a 1-tap "Mark as Paid". ClanTab never
/// processes money itself: marking paid just records that the payment
/// happened outside the app.
///
/// Takes the same `GroupViewModel` instance `GroupHomeView` holds, rather than
/// a static snapshot, so "Mark as Paid" → `refetch()` naturally updates this
/// list (and the presenting screen) with the server's freshly recomputed plan.
struct SettleUpView: View {
    let groupId: String
    let client: ClanTabClient
    let accessToken: String?
    let viewModel: GroupViewModel
    let onSettled: () -> Void
    let onDone: () -> Void

    @State private var pendingRowId: String?
    @State private var errorMessage: String?
    /// The settlement `errorMessage` belongs to, so "Retry" can resubmit the
    /// exact same `markPaid` call rather than needing the user to find the
    /// row and tap "Mark as Paid" again (`CHECKLIST.md` UX audit [33]).
    @State private var failedSettlement: SimplifiedSettlement?
    /// The amount that failed alongside `failedSettlement` — R11 made that
    /// amount editable, so "Retry" has to resubmit *that* figure, not
    /// silently fall back to the full suggested `settlement.amountMinor`.
    @State private var failedAmountMinor: Int64?
    @State private var confirmingSettlement: SimplifiedSettlement?
    /// The shareable recap card (`CHECKLIST.md`), rendered off-screen once the
    /// plan is in hand and re-rendered whenever it changes.
    @State private var shareCard: Image?
    /// Which rows the share card includes (`CHECKLIST.md` R10) — `nil` means
    /// "everything," the default; a customized set is keyed by `rowId(for:)`.
    @State private var shareSelection: Set<String>?
    @State private var isPresentingShareCustomize = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.coachMarks) private var coachMarks
    /// Mirrors `coachMarks?.hasSeen` so dismissing the UPI nudge below
    /// re-renders immediately, same pattern as `AuthViewModel.syncNudgeDismissed`.
    @State private var hasSeenUpiNudge = false

    private var members: [Member] {
        viewModel.state?.members ?? []
    }

    private var settlements: [SimplifiedSettlement] {
        viewModel.state?.simplifiedSettlements ?? []
    }

    /// Whether to show the one-time "add your UPI ID" nudge
    /// (`CHECKLIST.md` UX audit [24]) — the "Pay via UPI" link on a row
    /// (`upiPayURL(for:)`) only ever appears for a *payee* who's already set
    /// one, so someone who's owed money in this plan and hasn't set theirs
    /// would otherwise never learn the field exists. Gated on being owed
    /// something in INR specifically, since UPI has no other currency.
    private var shouldShowUpiNudge: Bool {
        guard !hasSeenUpiNudge, let myId = viewModel.myIdentity?.memberId else { return false }
        guard let me = members.first(where: { $0.id == myId }), me.upiVpa == nil else { return false }
        return settlements.contains { $0.toId == myId && $0.currency == "INR" }
    }

    /// `shareSelection` materialized to every row when it's still `nil`
    /// (nothing customized yet) — what the picker checks against and what
    /// `selectedSettlements` filters by.
    private var effectiveShareSelection: Set<String> {
        shareSelection ?? Set(settlements.map(rowId(for:)))
    }

    private var shareSelectionBinding: Binding<Set<String>> {
        Binding(get: { effectiveShareSelection }, set: { shareSelection = $0 })
    }

    /// The settlements the share card actually renders — everything, unless
    /// customized down via `ShareCardRowPicker` (`CHECKLIST.md` R10).
    private var selectedSettlements: [SimplifiedSettlement] {
        settlements.filter { effectiveShareSelection.contains(rowId(for: $0)) }
    }

    /// The plan grouped into per-currency sections, in the order currencies
    /// first appear (matching the server's `simplifiedSettlements` order).
    private var settlementsByCurrency: [(currency: String, items: [SimplifiedSettlement])] {
        var order: [String] = []
        var groups: [String: [SimplifiedSettlement]] = [:]
        for s in settlements {
            if groups[s.currency] == nil { order.append(s.currency) }
            groups[s.currency, default: []].append(s)
        }
        return order.map { ($0, groups[$0] ?? []) }
    }

    var body: some View {
        List {
            if settlements.isEmpty {
                Section {
                    Text("Everyone is settled up.").foregroundStyle(.secondary)
                }
            } else {
                ForEach(settlementsByCurrency, id: \.currency) { group in
                    Section(settlementsByCurrency.count > 1 ? group.currency : "") {
                        ForEach(group.items, id: \.self) { settlement in
                            settlementRow(settlement)
                        }
                    }
                }
            }

            if shouldShowUpiNudge {
                upiNudgeSection
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                    // Resubmits the exact settlement that failed
                    // (`CHECKLIST.md` UX audit [33]) — most useful for the
                    // offline case, where nothing else changed and trying
                    // again is the entire fix.
                    if let failedSettlement {
                        Button("Retry") {
                            Task { await markPaid(failedSettlement, amountMinor: failedAmountMinor, rowId: rowId(for: failedSettlement)) }
                        }
                        .disabled(pendingRowId != nil)
                    }
                }
            }
        }
        .materialSheetContent()
        .navigationTitle("Settle Up")
        .onAppear {
            hasSeenUpiNudge = coachMarks?.hasSeen("settleUp.addUpiId") ?? true
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done", action: onDone)
            }
            if !settlements.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingShareCustomize = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Customize what the share card includes")
                }
            }
            if let shareCard {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(
                        item: shareCard,
                        preview: SharePreview("\(groupName) — settle up", image: shareCard)
                    ) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: shareSelection) { renderShareCard() }
        .task(id: settlements) { renderShareCard() }
        .sheet(isPresented: $isPresentingShareCustomize) {
            NavigationStack {
                ShareCardRowPicker(
                    rows: settlements.map { s in
                        ShareCardRow(
                            id: rowId(for: s),
                            title: "\(name(for: s.fromId)) → \(name(for: s.toId))",
                            subtitle: MoneyFormat.string(minorUnits: s.amountMinor, currency: s.currency)
                        )
                    },
                    selection: shareSelectionBinding
                )
            }
            .materialSheet()
        }
        .sheet(isPresented: Binding(get: { confirmingSettlement != nil }, set: { if !$0 { confirmingSettlement = nil } })) {
            if let settlement = confirmingSettlement {
                NavigationStack {
                    ConfirmSettlementView(
                        settlement: settlement,
                        payerName: name(for: settlement.fromId),
                        payeeName: name(for: settlement.toId),
                        onConfirm: { amountMinor in
                            confirmingSettlement = nil
                            Task { await markPaid(settlement, amountMinor: amountMinor, rowId: rowId(for: settlement)) }
                        },
                        onCancel: { confirmingSettlement = nil }
                    )
                }
                .materialSheet()
            }
        }
    }

    private func rowId(for settlement: SimplifiedSettlement) -> String {
        "\(settlement.currency):\(settlement.fromId)->\(settlement.toId)"
    }

    @MainActor
    private func renderShareCard() {
        shareCard = RecapCard.render(RecapCard(
            groupName: groupName,
            groupEmoji: viewModel.state?.group.emoji,
            members: members,
            content: .settleUp(selectedSettlements)
        ))
    }

    private func dismissUpiNudge() {
        coachMarks?.markSeen("settleUp.addUpiId")
        withAnimation(.easeOut(duration: 0.15)) { hasSeenUpiNudge = true }
    }

    private var groupName: String { viewModel.state?.group.name ?? "Your group" }

    /// Extracted into its own computed property — folding this `Section`
    /// straight into `body`'s `List` pushed the type-checker over the edge
    /// (a recurring pattern in this codebase; see `GroupSettingsView`'s
    /// `joinCodeSection`).
    private var upiNudgeSection: some View {
        Section {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "indianrupeesign.circle")
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Get paid via UPI")
                        .font(.subheadline.weight(.semibold))
                    Text("Add your UPI ID under Group Settings → My UPI ID, so whoever pays you here gets a one-tap link.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button(action: dismissUpiNudge) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.vertical, 2)
        }
    }

    private func settlementRow(_ settlement: SimplifiedSettlement) -> some View {
        let rowId = rowId(for: settlement)
        let payer = name(for: settlement.fromId)
        let payee = name(for: settlement.toId)
        let amount = MoneyFormat.string(minorUnits: settlement.amountMinor, currency: settlement.currency)
        let markPaidButton = Button {
            confirmingSettlement = settlement
        } label: {
            Group {
                if pendingRowId == rowId {
                    ProgressView()
                } else {
                    Text("Mark as Paid").lineLimit(1)
                }
            }
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .disabled(pendingRowId != nil)
        .accessibilityLabel("Mark \(payer)'s \(amount) payment to \(payee) as paid")

        let summary = VStack(alignment: .leading, spacing: 2) {
            Text("\(payer) pays \(payee)")
            Text(amount).font(.headline).lineLimit(1)
        }
        .accessibilityElement(children: .combine)

        return VStack(alignment: .leading, spacing: 8) {
            // At accessibility text sizes the button can't sit beside the
            // names without both wrapping badly — it drops full-width below.
            if dynamicTypeSize.isAccessibilitySize {
                HStack(alignment: .top) { MemberAvatar(name: payer, size: 32); summary }
                markPaidButton
            } else {
                HStack {
                    MemberAvatar(name: payer, size: 32)
                    summary
                    Spacer()
                    markPaidButton
                }
            }
            if let upiURL = upiPayURL(for: settlement) {
                Link(destination: upiURL) {
                    Label("Pay via UPI", systemImage: "indianrupeesign.circle")
                }
                .font(.subheadline)
                .accessibilityLabel("Open a UPI app to pay \(payee) \(amount)")
            }
        }
        .padding(.vertical, 4)
    }

    private func name(for memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    /// A plain `upi://pay?...` deep link handing off to whichever UPI app the
    /// payer has installed (`FEATURE_BACKLOG.md` "UPI deep link on Settle
    /// Up") — ClanTab never sees or moves the money, just constructs the
    /// URI. `nil` unless the payee has set a UPI VPA and the settlement is
    /// actually in INR (UPI's only currency).
    private func upiPayURL(for settlement: SimplifiedSettlement) -> URL? {
        guard let payee = members.first(where: { $0.id == settlement.toId }) else { return nil }
        return UPIPayLink.url(
            vpa: payee.upiVpa,
            payeeName: payee.displayName,
            amountMinor: settlement.amountMinor,
            currency: settlement.currency
        )
    }

    /// `amountMinor` is whatever `ConfirmSettlementView` confirmed — partial
    /// settlement (`CHECKLIST.md` R11) — falling back to the full suggested
    /// `settlement.amountMinor` only when nothing else set it. The balance
    /// math already handles a partial amount correctly (simple subtraction);
    /// this was purely a missing input field, no server change needed.
    private func markPaid(_ settlement: SimplifiedSettlement, amountMinor: Int64? = nil, rowId: String) async {
        let resolvedAmountMinor = amountMinor ?? settlement.amountMinor
        pendingRowId = rowId
        errorMessage = nil
        failedSettlement = nil
        failedAmountMinor = nil
        defer { pendingRowId = nil }

        do {
            _ = try await client.addSettlement(
                groupId: groupId,
                AddSettlementRequest(
                    id: UUID().uuidString,
                    fromId: settlement.fromId,
                    toId: settlement.toId,
                    amountMinor: resolvedAmountMinor,
                    currency: settlement.currency
                ),
                accessToken: accessToken
            )
            onSettled()
            await viewModel.refetch()
        } catch {
            errorMessage = friendlyMessage(for: error)
            failedSettlement = settlement
            failedAmountMinor = resolvedAmountMinor
        }
    }
}

/// The confirm step for "Mark as Paid" — an editable amount, defaulted to
/// the full suggested `settlement.amountMinor` (`CHECKLIST.md` R11: half of
/// real-world settling is "I paid them part of it for now"). Sibling type in
/// this file rather than its own, same as `ReceiptViewer` living alongside
/// `ReceiptThumbnail` — small, single-caller, tightly coupled to the screen
/// that presents it.
private struct ConfirmSettlementView: View {
    let settlement: SimplifiedSettlement
    let payerName: String
    let payeeName: String
    let onConfirm: (Int64) -> Void
    let onCancel: () -> Void

    @State private var amountText: String

    init(settlement: SimplifiedSettlement, payerName: String, payeeName: String, onConfirm: @escaping (Int64) -> Void, onCancel: @escaping () -> Void) {
        self.settlement = settlement
        self.payerName = payerName
        self.payeeName = payeeName
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _amountText = State(initialValue: MoneyFormat.plainString(minorUnits: settlement.amountMinor))
    }

    private var amountMinor: Int64? { MoneyFormat.minorUnits(from: amountText) }
    private var isFullAmount: Bool { amountMinor == settlement.amountMinor }

    var body: some View {
        Form {
            Section {
                Text("\(payerName) pays \(payeeName)")
                HStack {
                    TextField("0.00", text: $amountText)
                        .keyboardType(.decimalPad)
                        .font(.title2.weight(.semibold))
                    Text(settlement.currency).foregroundStyle(.secondary)
                }
                if let amountMinor, !isFullAmount {
                    let suggested = MoneyFormat.string(minorUnits: settlement.amountMinor, currency: settlement.currency)
                    Text(
                        amountMinor < settlement.amountMinor
                            ? "Partial payment — the suggested amount was \(suggested)."
                            : "More than the suggested \(suggested)."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text("ClanTab just records this as settled — it doesn't move any money.")
            }
        }
        .navigationTitle("Mark as Paid")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Confirm") {
                    guard let amountMinor else { return }
                    onConfirm(amountMinor)
                }
                .disabled((amountMinor ?? 0) <= 0)
            }
        }
    }
}
