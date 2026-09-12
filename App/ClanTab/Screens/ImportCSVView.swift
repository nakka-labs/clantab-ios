import SwiftUI
import UniformTypeIdentifiers
import ClanTabKit

/// Imports expense history from a CSV (ClanTab's own export, or Splitwise's).
/// Pure parsing is `ClanTabKit.CSVImport`; this view picks the file, lets the
/// user match the names in it to real members (or create them), then posts each
/// row with a client-generated id (so a partial import is safe to retry).
struct ImportCSVView: View {
    let groupId: String
    let existingMembers: [Member]
    /// The group's current ledger — checked against every parsed row so an
    /// already-imported file (or the same trip exported from two apps by two
    /// members) can be flagged before posting, not just warned about in the
    /// abstract (`CHECKLIST.md` "De-dupe guard on CSV import").
    let existingExpenses: [Expense]
    let existingSettlements: [Settlement]
    let client: ClanTabClient
    let accessToken: String?
    let onImported: () -> Void
    let onCancel: () -> Void

    private enum Stage {
        case pickFile
        case review(CSVImport.Result)
        case importing(done: Int, total: Int)
        case finished(imported: Int, failed: [FailedRow], message: String? = nil)
    }

    /// One row that parsed fine but the server rejected — surfaced by row and
    /// reason, not just a bare count (`CHECKLIST.md` "CSV import: identify
    /// failed rows, not just a count").
    private struct FailedRow: Identifiable {
        let id = UUID()
        let label: String
        let reason: String
    }

    /// How to resolve one name from the CSV.
    private enum NameChoice: Hashable {
        case match(memberId: String)
        case create
        case skip
    }

    @State private var stage: Stage = .pickFile
    @State private var isPickingFile = false
    @State private var choices: [String: NameChoice] = [:]
    @State private var parseError: String?
    /// Whether a row that looks like it's already in the ledger is left out
    /// of the import. Defaults on — the safer default for a guard whose
    /// whole point is to stop an accidental double-post; a user who really
    /// does want a flagged row re-added can still turn this off.
    @State private var skipLikelyDuplicates = true

    var body: some View {
        Group {
            switch stage {
            case .pickFile:      pickFile
            case .review(let r): review(r)
            case .importing(let done, let total):
                ProgressView("Importing \(done) of \(total)…")
            case .finished(let imported, let failed, let message):
                finished(imported: imported, failed: failed, message: message)
            }
        }
        .materialSheetContent()
        .navigationTitle("Import CSV")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]
        ) { result in
            handlePickedFile(result)
        }
    }

    // MARK: stages

    private var pickFile: some View {
        ContentUnavailableView {
            Label("Import from CSV", systemImage: "square.and.arrow.down")
        } description: {
            Text("Moving over from Splitwise or Settle Up, or restoring a ClanTab export? Bring the whole expense history with you.")
        } actions: {
            Button("Choose a File…") { isPickingFile = true }
                .buttonStyle(.borderedProminent)
            if let parseError {
                Text(parseError).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private func review(_ result: CSVImport.Result) -> some View {
        Form {
            Section {
                LabeledContent("Format", value: formatLabel(result.format))
                LabeledContent("Expenses", value: "\(result.expenses.count)")
                if !result.settlements.isEmpty {
                    LabeledContent("Settlements", value: "\(result.settlements.count)")
                }
            }

            if !result.referencedNames.isEmpty {
                Section("Match people") {
                    ForEach(result.referencedNames, id: \.self) { name in
                        Picker(name, selection: choiceBinding(for: name)) {
                            ForEach(existingMembers) { member in
                                Text(member.displayName).tag(NameChoice.match(memberId: member.id))
                            }
                            Text("Add as new member").tag(NameChoice.create)
                            Text("Skip their rows").tag(NameChoice.skip)
                        }
                    }
                }
            }

            if !result.warnings.isEmpty {
                Section("\(result.warnings.count) row\(result.warnings.count == 1 ? "" : "s") skipped") {
                    ForEach(result.warnings, id: \.self) { warning in
                        Text(warning).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            // `CHECKLIST.md` "De-dupe guard on CSV import" — every row that
            // looks like it's already in the group's ledger (`CSVDuplicateCheck`:
            // same date, amount, payer, and description, allowing for another
            // app's own rounding) gets flagged and excluded by default, so
            // re-importing the same file — or the same trip exported from two
            // apps by two different members — no longer silently doubles
            // everything.
            if duplicateCount(result) > 0 {
                duplicatesSection(result)
            }
            stillOnlyBestEffortSection(result)

            Section {
                Button("Import") {
                    Task { await runImport(result) }
                }
                .disabled(importableCount(result) == 0)
            } footer: {
                Text("\(importableCount(result)) of \(result.expenses.count + result.settlements.count) rows will be imported.")
            }
        }
    }

    private func finished(imported: Int, failed: [FailedRow], message: String?) -> some View {
        Group {
            if failed.isEmpty {
                ContentUnavailableView {
                    Label("Imported \(imported) rows", systemImage: "checkmark.circle")
                } description: {
                    if let message { Text(message) }
                } actions: {
                    Button("Done") { onImported() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                // A bare count doesn't say which rows or why (`CHECKLIST.md`
                // "CSV import: identify failed rows, not just a count") —
                // list each one so a retry (fix the source file, re-import)
                // is actually possible.
                Form {
                    Section {
                        Label(
                            "Imported \(imported), \(failed.count) failed",
                            systemImage: "exclamationmark.triangle"
                        )
                        if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("\(failed.count) row\(failed.count == 1 ? "" : "s") couldn't be saved") {
                        ForEach(failed) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.label).font(.subheadline)
                                Text(row.reason).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Section {
                        Button("Done") { onImported() }
                    }
                }
            }
        }
    }

    private static let rowDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private func rowLabel(_ draft: CSVImport.DraftExpense) -> String {
        "\(Self.rowDateFormatter.string(from: draft.date)) — \(draft.description)"
    }

    private func rowLabel(_ draft: CSVImport.DraftSettlement) -> String {
        "\(Self.rowDateFormatter.string(from: draft.date)) — Settlement: \(draft.fromName) → \(draft.toName)"
    }

    // MARK: format label

    private func formatLabel(_ format: CSVImport.Format) -> String {
        switch format {
        case .clanTab: return "ClanTab export"
        case .splitwise: return "Splitwise export"
        case .settleUp: return "Settle Up export"
        }
    }

    // MARK: name choices

    private func choiceBinding(for name: String) -> Binding<NameChoice> {
        Binding(
            get: { choices[name] ?? defaultChoice(for: name) },
            set: { choices[name] = $0 }
        )
    }

    private func defaultChoice(for name: String) -> NameChoice {
        if let match = existingMembers.first(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
            return .match(memberId: match.id)
        }
        return .create
    }

    private func resolvedChoice(for name: String) -> NameChoice {
        choices[name] ?? defaultChoice(for: name)
    }

    /// Rows where every referenced name resolves to a member (not `.skip`),
    /// and — while `skipLikelyDuplicates` is on — that don't look like
    /// they're already in the group's ledger.
    private func importableCount(_ result: CSVImport.Result) -> Int {
        let usable: (Set<String>) -> Bool = { names in
            names.allSatisfy { resolvedChoice(for: $0) != .skip }
        }
        let expenses = result.expenses.filter {
            usable(Set([$0.payerName] + $0.splits.map(\.memberName))) && !isExcludedAsDuplicate($0)
        }
        let settlements = result.settlements.filter {
            usable(Set([$0.fromName, $0.toName])) && !isExcludedAsDuplicate($0)
        }
        return expenses.count + settlements.count
    }

    // MARK: duplicate detection (`CHECKLIST.md` "De-dupe guard on CSV import")

    /// `true` once the referenced name(s) resolve to real (already-existing)
    /// members and the row matches something already in the group's ledger
    /// by date, amount, payer, and description (`CSVDuplicateCheck`). A row
    /// whose payer is being created fresh (`.create`) can never match — the
    /// member doesn't exist in the ledger yet.
    private func isLikelyDuplicate(_ draft: CSVImport.DraftExpense) -> Bool {
        guard case .match(let payerId) = resolvedChoice(for: draft.payerName) else { return false }
        return CSVDuplicateCheck.isLikelyDuplicate(draft, payerId: payerId, against: existingExpenses)
    }

    private func isLikelyDuplicate(_ draft: CSVImport.DraftSettlement) -> Bool {
        guard case .match(let fromId) = resolvedChoice(for: draft.fromName),
              case .match(let toId) = resolvedChoice(for: draft.toName)
        else { return false }
        return CSVDuplicateCheck.isLikelyDuplicate(draft, fromId: fromId, toId: toId, against: existingSettlements)
    }

    /// Whether `skipLikelyDuplicates` actually excludes this specific row —
    /// i.e. the toggle is on *and* the row is flagged. Split out from
    /// `isLikelyDuplicate` so the toggle only ever changes what's imported,
    /// never what's *shown* as flagged.
    private func isExcludedAsDuplicate(_ draft: CSVImport.DraftExpense) -> Bool {
        skipLikelyDuplicates && isLikelyDuplicate(draft)
    }

    private func isExcludedAsDuplicate(_ draft: CSVImport.DraftSettlement) -> Bool {
        skipLikelyDuplicates && isLikelyDuplicate(draft)
    }

    private func likelyDuplicateExpenses(_ result: CSVImport.Result) -> [CSVImport.DraftExpense] {
        result.expenses.filter(isLikelyDuplicate)
    }

    private func likelyDuplicateSettlements(_ result: CSVImport.Result) -> [CSVImport.DraftSettlement] {
        result.settlements.filter(isLikelyDuplicate)
    }

    private func duplicateCount(_ result: CSVImport.Result) -> Int {
        likelyDuplicateExpenses(result).count + likelyDuplicateSettlements(result).count
    }

    /// Extracted into its own computed property/function rather than folded
    /// straight into `review`'s `Form` — the type-checker complexity this
    /// codebase keeps hitting when several conditionals and `ForEach`s stack
    /// up in one `body` (see `GroupSettingsView.joinCodeSection`,
    /// `SettleUpView.upiNudgeSection`).
    private func duplicatesSection(_ result: CSVImport.Result) -> some View {
        let count = duplicateCount(result)
        return Section {
            Toggle("Skip likely duplicates", isOn: $skipLikelyDuplicates)
            ForEach(Array(likelyDuplicateExpenses(result).enumerated()), id: \.offset) { _, draft in
                Text(rowLabel(draft)).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(likelyDuplicateSettlements(result).enumerated()), id: \.offset) { _, draft in
                Text(rowLabel(draft)).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("\(count) row\(count == 1 ? "" : "s") already in this group")
        } footer: {
            Text("Same date, amount, payer, and description as something already here — probably a re-import. Turn the toggle off to bring them back in.")
        }
    }

    /// The heuristic's own limits, worth stating regardless of whether
    /// anything was actually flagged this time — it can only compare against
    /// names already resolved to real members, and a source app that
    /// describes the same expense differently won't match by description.
    private func stillOnlyBestEffortSection(_ result: CSVImport.Result) -> some View {
        Section {
            Label {
                Text(
                    duplicateCount(result) > 0
                        ? "This is a best-effort check — a row worded differently by the source app can still slip through as a new one."
                        : "ClanTab flags rows that match something already here by date, amount, payer, and description — but a differently-worded export can still slip through."
                )
                .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.orange)
        }
    }

    // MARK: file + import

    private func handlePickedFile(_ result: Result<URL, Error>) {
        parseError = nil
        switch result {
        case .failure(let error):
            parseError = error.localizedDescription
        case .success(let url):
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                guard let text = CSVImport.decode(data) else {
                    parseError = "Couldn't read that file — unrecognised text encoding."
                    return
                }
                let parsed = try CSVImport.parse(text)
                choices = [:]
                stage = .review(parsed)
            } catch let error as CSVImport.ParseError {
                parseError = message(for: error)
            } catch {
                parseError = "Couldn't read that file."
            }
        }
    }

    private func message(for error: CSVImport.ParseError) -> String {
        switch error {
        case .empty: return "That file is empty."
        case .noDataRows: return "That file has a header but no rows."
        case .unrecognizedFormat:
            return "Unrecognised format. Use a ClanTab export, a Splitwise export, or a Settle Up export."
        }
    }

    private func runImport(_ result: CSVImport.Result) async {
        // 1. Resolve names → member ids, creating the ones marked `.create`.
        var idByName: [String: String] = [:]
        for member in existingMembers {
            idByName[member.displayName.lowercased()] = member.id
        }
        for name in result.referencedNames {
            switch resolvedChoice(for: name) {
            case .match(let memberId):
                idByName[name.lowercased()] = memberId
            case .create:
                do {
                    let joined = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: name), accessToken: accessToken)
                    idByName[name.lowercased()] = joined.member.id
                } catch {
                    stage = .finished(imported: 0, failed: [], message: "Couldn't add member \"\(name)\": \(friendlyMessage(for: error))")
                    return
                }
            case .skip:
                break
            }
        }

        func id(_ name: String) -> String? { idByName[name.lowercased()] }
        func resolvable(_ names: [String]) -> Bool { names.allSatisfy { resolvedChoice(for: $0) != .skip && id($0) != nil } }

        let expenses = result.expenses.filter {
            resolvable([$0.payerName] + $0.splits.map(\.memberName)) && !isExcludedAsDuplicate($0)
        }
        let settlements = result.settlements.filter {
            resolvable([$0.fromName, $0.toName]) && !isExcludedAsDuplicate($0)
        }
        let total = expenses.count + settlements.count

        var done = 0
        var failed: [FailedRow] = []
        stage = .importing(done: 0, total: total)

        for draft in expenses {
            do {
                _ = try await client.addExpense(groupId: groupId, AddExpenseRequest(
                    id: UUID().uuidString,
                    payerId: id(draft.payerName)!,
                    amountMinor: draft.amountMinor,
                    currency: draft.currency,
                    description: draft.description,
                    date: draft.date,
                    splitType: .exact,
                    splits: draft.splits.map { ExpenseSplit(memberId: id($0.memberName)!, amountMinor: $0.amountMinor) },
                    category: draft.category,
                    categoryIcon: draft.category == nil ? nil : "tag"
                ), accessToken: accessToken)
            } catch {
                failed.append(FailedRow(label: rowLabel(draft), reason: friendlyMessage(for: error)))
            }
            done += 1
            stage = .importing(done: done, total: total)
        }

        for draft in settlements {
            do {
                _ = try await client.addSettlement(groupId: groupId, AddSettlementRequest(
                    id: UUID().uuidString,
                    fromId: id(draft.fromName)!,
                    toId: id(draft.toName)!,
                    amountMinor: draft.amountMinor,
                    currency: draft.currency
                ), accessToken: accessToken)
            } catch {
                failed.append(FailedRow(label: rowLabel(draft), reason: friendlyMessage(for: error)))
            }
            done += 1
            stage = .importing(done: done, total: total)
        }

        let skippedDuplicates = skipLikelyDuplicates ? duplicateCount(result) : 0
        stage = .finished(
            imported: total - failed.count, failed: failed,
            message: skippedDuplicates > 0
                ? "Skipped \(skippedDuplicates) row\(skippedDuplicates == 1 ? "" : "s") that looked already imported."
                : nil
        )
    }
}
