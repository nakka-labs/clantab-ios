import Foundation

/// Parses a CSV of expense history into drafts ready to be posted to a group.
/// Pure: no I/O, no member resolution — drafts carry member *names*, and the
/// caller (the App's import flow) matches those to real members or creates them.
///
/// Two formats are auto-detected:
///  - **ClanTab** — this app's own `Export.csv` output, for backup/restore or
///    moving history between groups (lossless round-trip).
///  - **Splitwise** — Splitwise's per-person CSV export. Each row's per-person
///    column is that person's signed net (paid − owed); a row is reconstructed
///    as a single-payer expense (payer = the person with the largest net).
///    Rows Splitwise can't represent losslessly (a genuine multi-payer split)
///    are skipped with a warning.
public enum CSVImport {
    public enum Format: String, Sendable, Equatable {
        case clanTab
        case splitwise
    }

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case unrecognizedFormat
        case noDataRows
    }

    public struct DraftSplit: Equatable, Hashable, Sendable {
        public let memberName: String
        public let amountMinor: Int64
        public init(memberName: String, amountMinor: Int64) {
            self.memberName = memberName
            self.amountMinor = amountMinor
        }
    }

    public struct DraftExpense: Equatable, Sendable {
        public let date: Date
        public let description: String
        public let amountMinor: Int64
        public let currency: String
        public let payerName: String
        public let splits: [DraftSplit]
        public let category: String?
        public init(
            date: Date, description: String, amountMinor: Int64, currency: String,
            payerName: String, splits: [DraftSplit], category: String?
        ) {
            self.date = date
            self.description = description
            self.amountMinor = amountMinor
            self.currency = currency
            self.payerName = payerName
            self.splits = splits
            self.category = category
        }
    }

    public struct DraftSettlement: Equatable, Sendable {
        public let date: Date
        public let fromName: String
        public let toName: String
        public let amountMinor: Int64
        public let currency: String
        public init(date: Date, fromName: String, toName: String, amountMinor: Int64, currency: String) {
            self.date = date
            self.fromName = fromName
            self.toName = toName
            self.amountMinor = amountMinor
            self.currency = currency
        }
    }

    public struct Result: Equatable, Sendable {
        public let format: Format
        public let expenses: [DraftExpense]
        public let settlements: [DraftSettlement]
        /// Distinct member names referenced anywhere, first-seen order — the
        /// list the import UI asks the user to match.
        public let referencedNames: [String]
        /// Human-readable notes about rows that were skipped or adjusted.
        public let warnings: [String]
    }

    public static func parse(_ text: String) throws -> Result {
        let rows = tokenize(text).filter { row in row.contains { !$0.isEmpty } }
        guard let header = rows.first else { throw ParseError.empty }
        let dataRows = Array(rows.dropFirst())
        guard !dataRows.isEmpty else { throw ParseError.noDataRows }

        let lowered = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

        if lowered == ["type", "date", "description", "category", "from", "to", "amount", "currency", "splits"] {
            return parseClanTab(dataRows)
        }
        if lowered.contains("cost"), lowered.contains("currency"),
           lowered.contains("date"), lowered.contains("description") {
            return parseSplitwise(header: header, lowered: lowered, dataRows: dataRows)
        }
        throw ParseError.unrecognizedFormat
    }

    // MARK: - ClanTab

    private static func parseClanTab(_ rows: [[String]]) -> Result {
        var expenses: [DraftExpense] = []
        var settlements: [DraftSettlement] = []
        var names = OrderedNames()
        var warnings: [String] = []

        for (i, row) in rows.enumerated() where row.count >= 9 {
            let type = row[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard let date = parseDate(row[1]),
                  let amount = parseAmount(row[6]), amount > 0 else {
                warnings.append("Row \(i + 2): couldn't read the date or amount — skipped.")
                continue
            }
            let currency = row[7].trimmingCharacters(in: .whitespaces)

            switch type {
            case "expense":
                let payer = row[4].trimmingCharacters(in: .whitespaces)
                let splits = parseClanTabSplits(row[8])
                guard !payer.isEmpty, !splits.isEmpty,
                      splits.reduce(Int64(0), { $0 + $1.amountMinor }) == amount else {
                    warnings.append("Row \(i + 2): splits don't add up to the amount — skipped.")
                    continue
                }
                names.add(payer)
                splits.forEach { names.add($0.memberName) }
                let category = row[3].trimmingCharacters(in: .whitespaces)
                expenses.append(DraftExpense(
                    date: date, description: row[2], amountMinor: amount, currency: currency,
                    payerName: payer, splits: splits, category: category.isEmpty ? nil : category
                ))
            case "settlement":
                let from = row[4].trimmingCharacters(in: .whitespaces)
                let to = row[5].trimmingCharacters(in: .whitespaces)
                guard !from.isEmpty, !to.isEmpty, from != to else {
                    warnings.append("Row \(i + 2): settlement needs two different people — skipped.")
                    continue
                }
                names.add(from)
                names.add(to)
                settlements.append(DraftSettlement(
                    date: date, fromName: from, toName: to, amountMinor: amount, currency: currency
                ))
            default:
                warnings.append("Row \(i + 2): unknown row type \"\(row[0])\" — skipped.")
            }
        }

        return Result(format: .clanTab, expenses: expenses, settlements: settlements,
                      referencedNames: names.all, warnings: warnings)
    }

    /// `"Ana:12.50; Ben:7.50"` → `[DraftSplit]`. Splits on the LAST colon so a
    /// name containing a colon still parses.
    private static func parseClanTabSplits(_ field: String) -> [DraftSplit] {
        field.split(separator: ";").compactMap { part in
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.lastIndex(of: ":") else { return nil }
            let name = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            let amountText = String(trimmed[trimmed.index(after: colon)...])
            guard !name.isEmpty, let amount = parseAmount(amountText), amount >= 0 else { return nil }
            return DraftSplit(memberName: name, amountMinor: amount)
        }
    }

    // MARK: - Splitwise

    private static func parseSplitwise(header: [String], lowered: [String], dataRows: [[String]]) -> Result {
        let dateIdx = lowered.firstIndex(of: "date")!
        let descIdx = lowered.firstIndex(of: "description")!
        let costIdx = lowered.firstIndex(of: "cost")!
        let currencyIdx = lowered.firstIndex(of: "currency")!
        let categoryIdx = lowered.firstIndex(of: "category")
        // Everyone after the currency column is a person.
        let personIdxs = Array((currencyIdx + 1)..<header.count)
        let personNames = personIdxs.map { header[$0].trimmingCharacters(in: .whitespaces) }
            .enumerated().filter { !$0.element.isEmpty }

        var expenses: [DraftExpense] = []
        var names = OrderedNames()
        var warnings: [String] = []

        for (i, row) in dataRows.enumerated() {
            guard row.count > currencyIdx,
                  let date = parseDate(cell(row, dateIdx)) else { continue }
            let description = cell(row, descIdx)
            if description.lowercased() == "total balance" { continue }
            guard let cost = parseAmount(cell(row, costIdx)), cost > 0 else {
                if !cell(row, costIdx).isEmpty {
                    warnings.append("Row \(i + 2): couldn't read the cost — skipped.")
                }
                continue
            }
            let currency = cell(row, currencyIdx)

            // Signed net per person.
            var nets: [(name: String, net: Int64)] = []
            for (offset, name) in personNames {
                let value = parseSignedAmount(cell(row, personIdxs[offset])) ?? 0
                nets.append((name, value))
            }
            guard nets.contains(where: { $0.net != 0 }) else {
                warnings.append("Row \(i + 2): no-one is involved — skipped.")
                continue
            }

            // Single-payer reconstruction: payer paid the whole cost.
            let payer = nets.max { $0.net < $1.net }!
            var splits: [DraftSplit] = []
            var ok = true
            for entry in nets {
                let share = entry.name == payer.name ? cost - entry.net : -entry.net
                if share < 0 { ok = false; break }
                if share > 0 || entry.name == payer.name {
                    splits.append(DraftSplit(memberName: entry.name, amountMinor: share))
                }
            }
            guard ok, splits.reduce(Int64(0), { $0 + $1.amountMinor }) == cost, payer.net > 0 else {
                warnings.append("Row \(i + 2) (\"\(description)\"): a multi-payer split Splitwise can't export losslessly — skipped.")
                continue
            }

            names.add(payer.name)
            splits.forEach { names.add($0.memberName) }
            let category = categoryIdx.map { cell(row, $0) } ?? ""
            expenses.append(DraftExpense(
                date: date, description: description, amountMinor: cost, currency: currency,
                payerName: payer.name, splits: splits,
                category: (category.isEmpty || category.lowercased() == "general") ? nil : category
            ))
        }

        return Result(format: .splitwise, expenses: expenses, settlements: [],
                      referencedNames: names.all, warnings: warnings)
    }

    // MARK: - Helpers

    private static func cell(_ row: [String], _ idx: Int) -> String {
        idx < row.count ? row[idx].trimmingCharacters(in: .whitespaces) : ""
    }

    /// RFC 4180 tokenizer — handles quoted fields containing commas, quotes
    /// (doubled), and newlines. Accepts `\n` and `\r\n` line endings.
    static func tokenize(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" { field.append("\""); i += 2; continue }
                    inQuotes = false
                } else {
                    field.append(c)
                }
                i += 1
                continue
            }
            switch c {
            case "\"": inQuotes = true
            case ",": row.append(field); field = ""
            case "\r": break
            case "\n": row.append(field); rows.append(row); row = []; field = ""
            default: field.append(c)
            }
            i += 1
        }
        row.append(field)
        rows.append(row)
        return rows
    }

    /// A non-negative decimal ("12", "12.5", "12.50", "1,234.00") → minor units
    /// via integer math (never `Double`), truncated to 2 fractional digits.
    static func parseAmount(_ input: String) -> Int64? {
        guard let value = parseSignedAmount(input), value >= 0 else { return nil }
        return value
    }

    /// Signed decimal → minor units (Splitwise's per-person columns can be
    /// negative).
    static func parseSignedAmount(_ input: String) -> Int64? {
        var s = input.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "")
        guard !s.isEmpty else { return nil }
        let negative = s.hasPrefix("-")
        if negative { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }
        let wholeText = parts[0].isEmpty ? "0" : String(parts[0])
        guard wholeText.allSatisfy(\.isNumber), let whole = Int64(wholeText) else { return nil }
        var frac: Int64 = 0
        if parts.count == 2 {
            var f = String(parts[1])
            guard f.allSatisfy(\.isNumber) else { return nil }
            if f.count > 2 { f = String(f.prefix(2)) }
            while f.count < 2 { f.append("0") }
            frac = Int64(f) ?? 0
        }
        let value = whole * 100 + frac
        return negative ? -value : value
    }

    static func parseDate(_ input: String) -> Date? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if let iso = ISO8601DateFormatter().date(from: trimmed) { return iso }
        let ymd = DateFormatter()
        ymd.calendar = Calendar(identifier: .gregorian)
        ymd.locale = Locale(identifier: "en_US_POSIX")
        ymd.timeZone = TimeZone(identifier: "UTC")
        ymd.dateFormat = "yyyy-MM-dd"
        return ymd.date(from: trimmed)
    }

    /// Distinct names in first-seen order, deduped case-insensitively (keeping
    /// the first casing seen).
    private struct OrderedNames {
        private var seen: Set<String> = []
        private(set) var all: [String] = []
        mutating func add(_ name: String) {
            let key = name.lowercased()
            guard !name.isEmpty, seen.insert(key).inserted else { return }
            all.append(name)
        }
    }
}
