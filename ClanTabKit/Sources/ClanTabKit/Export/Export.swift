import Foundation

/// CSV/JSON export of a group's ledger — per `PLAN.md`'s Export screen and
/// `README.md`'s "Data Ownership" pledge (full export at any time).
///
/// Pure functions: no I/O, no UI. The App target hands the returned
/// `String`/`Data` to `ShareLink`; writing it to a temp file for sharing is
/// the app's concern, not this package's.
public enum Export {
    /// One row per expense or settlement, oldest first. Money is rendered as
    /// a plain decimal string (e.g. "12.50") built from integer math — never
    /// `Double` — since this is the export/display boundary, not further
    /// arithmetic (see `AGENTS.md`).
    public static func csv(
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) -> String {
        func name(for memberId: String) -> String {
            members.first { $0.id == memberId }?.displayName ?? memberId
        }

        struct Row {
            let date: Date
            let line: String
        }

        var rows: [Row] = []

        for expense in expenses {
            let splits = expense.splits
                .map { "\(name(for: $0.memberId)):\(decimalString($0.amountMinor))" }
                .joined(separator: "; ")
            let fields = [
                "Expense",
                iso8601(expense.date),
                csvField(expense.description),
                csvField(expense.category ?? ""),
                csvField(name(for: expense.payerId)),
                csvField(""),
                decimalString(expense.amountMinor),
                csvField(splits),
            ]
            rows.append(Row(date: expense.date, line: fields.joined(separator: ",")))
        }

        for settlement in settlements {
            let fields = [
                "Settlement",
                iso8601(settlement.date),
                csvField(""),
                csvField(""),
                csvField(name(for: settlement.fromId)),
                csvField(name(for: settlement.toId)),
                decimalString(settlement.amountMinor),
                csvField(""),
            ]
            rows.append(Row(date: settlement.date, line: fields.joined(separator: ",")))
        }

        rows.sort { $0.date < $1.date }

        var lines = ["Type,Date,Description,Category,From,To,Amount,Splits"]
        lines.append(contentsOf: rows.map(\.line))
        return lines.joined(separator: "\n")
    }

    /// A complete, lossless snapshot for backup/migration — every model type
    /// re-serialized as pretty-printed JSON with ISO 8601 dates.
    public static func json(
        groupName: String,
        currency: String,
        members: [Member],
        expenses: [Expense],
        settlements: [Settlement]
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(
            Snapshot(groupName: groupName, currency: currency, members: members, expenses: expenses, settlements: settlements)
        )
    }

    struct Snapshot: Codable {
        let groupName: String
        let currency: String
        let members: [Member]
        let expenses: [Expense]
        let settlements: [Settlement]
    }

    private static func decimalString(_ minorUnits: Int64) -> String {
        let whole = minorUnits / 100
        let fractional = minorUnits % 100
        return "\(whole).\(fractional < 10 ? "0" : "")\(fractional)"
    }

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// Wraps a field in quotes and escapes embedded quotes when it contains a
    /// comma, quote, or newline — the standard CSV escaping rule (RFC 4180).
    private static func csvField(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
