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

            Section {
                // No de-dup guard yet (`docs/csv-import-formats.md`, `CHECKLIST.md`
                // "De-dupe guard on CSV import") — ClanTab can't tell an imported
                // row from one it already has, so importing the same file twice,
                // or the same trip exported from two apps by two members, silently
                // doubles the ledger. Flag it here until real detection lands.
                Label {
                    Text("ClanTab won't skip expenses it already has. If this file was imported before — or another member imported the same trip — every row is added again.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
            }

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

    /// Rows where every referenced name resolves to a member (not `.skip`).
    private func importableCount(_ result: CSVImport.Result) -> Int {
        let usable: (Set<String>) -> Bool = { names in
            names.allSatisfy { resolvedChoice(for: $0) != .skip }
        }
        let expenses = result.expenses.filter { usable(Set([$0.payerName] + $0.splits.map(\.memberName))) }
        let settlements = result.settlements.filter { usable(Set([$0.fromName, $0.toName])) }
        return expenses.count + settlements.count
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

        let expenses = result.expenses.filter { resolvable([$0.payerName] + $0.splits.map(\.memberName)) }
        let settlements = result.settlements.filter { resolvable([$0.fromName, $0.toName]) }
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

        stage = .finished(imported: total - failed.count, failed: failed)
    }
}
