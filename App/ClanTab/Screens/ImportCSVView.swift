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
    let onImported: () -> Void
    let onCancel: () -> Void

    private enum Stage {
        case pickFile
        case review(CSVImport.Result)
        case importing(done: Int, total: Int)
        case finished(imported: Int, failed: Int, message: String?)
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
            Text("Bring in expense history from a ClanTab export or a Splitwise export.")
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
                LabeledContent("Format", value: result.format == .clanTab ? "ClanTab export" : "Splitwise export")
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
                Button("Import") {
                    Task { await runImport(result) }
                }
                .disabled(importableCount(result) == 0)
            } footer: {
                Text("\(importableCount(result)) of \(result.expenses.count + result.settlements.count) rows will be imported.")
            }
        }
    }

    private func finished(imported: Int, failed: Int, message: String?) -> some View {
        ContentUnavailableView {
            Label(
                failed == 0 ? "Imported \(imported) rows" : "Imported \(imported), \(failed) failed",
                systemImage: failed == 0 ? "checkmark.circle" : "exclamationmark.triangle"
            )
        } description: {
            if let message { Text(message) }
        } actions: {
            Button("Done") { onImported() }
                .buttonStyle(.borderedProminent)
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
                let text = try String(contentsOf: url, encoding: .utf8)
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
            return "Unrecognised format. Use a ClanTab export or a Splitwise export."
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
                    let joined = try await client.joinGroup(groupId: groupId, JoinGroupRequest(displayName: name))
                    idByName[name.lowercased()] = joined.member.id
                } catch {
                    stage = .finished(imported: 0, failed: 0, message: "Couldn't add member \"\(name)\": \(friendlyMessage(for: error))")
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
        var failed = 0
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
                ))
            } catch {
                failed += 1
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
                ))
            } catch {
                failed += 1
            }
            done += 1
            stage = .importing(done: done, total: total)
        }

        stage = .finished(
            imported: total - failed,
            failed: failed,
            message: failed == 0 ? nil : "\(failed) row\(failed == 1 ? "" : "s") couldn't be saved."
        )
    }
}
