import Foundation

/// Formats integer minor units for display — the one place money is converted
/// out of minor units, per `AGENTS.md`'s "convert at the UI formatting edge" rule.
///
/// Assumes 2 decimal minor units, true for every currency in the v1 picker
/// (INR/USD/EUR/GBP/AUD/CAD) but not universally (e.g. JPY has 0) — worth
/// revisiting if the currency list grows.
enum MoneyFormat {
    static func string(minorUnits: Int64, currency: String) -> String {
        let major = Double(minorUnits) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.string(from: NSNumber(value: major)) ?? "\(currency) \(major)"
    }

    /// A plain, editable decimal string (`"12.34"`, `"12.00"`, `"0.05"`) — no
    /// currency symbol or grouping — for pre-filling a text field when editing.
    /// Integer math, so it round-trips through `minorUnits(from:)` exactly.
    static func plainString(minorUnits: Int64) -> String {
        let sign = minorUnits < 0 ? "-" : ""
        let magnitude = abs(minorUnits)
        return "\(sign)\(magnitude / 100).\(String(format: "%02d", magnitude % 100))"
    }

    /// Parses a decimal amount typed by the user (e.g. "12", "12.5", "12.34")
    /// into integer minor units — via string/integer math, not `Double`, so a
    /// typed amount never picks up floating-point drift on the way in. Returns
    /// `nil` for anything that isn't a plain non-negative number with at most
    /// 2 fractional digits.
    static func minorUnits(from input: String) -> Int64? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 1 || parts.count == 2 else { return nil }

        let wholeDigits = parts[0].isEmpty ? "0" : String(parts[0])
        guard wholeDigits.allSatisfy(\.isNumber), let wholePart = Int64(wholeDigits) else { return nil }

        var fractionalMinor: Int64 = 0
        if parts.count == 2 {
            var fractionalDigits = String(parts[1])
            guard fractionalDigits.count <= 2, fractionalDigits.allSatisfy(\.isNumber) else { return nil }
            while fractionalDigits.count < 2 { fractionalDigits.append("0") }
            guard let value = Int64(fractionalDigits) else { return nil }
            fractionalMinor = value
        }

        return wholePart * 100 + fractionalMinor
    }
}
