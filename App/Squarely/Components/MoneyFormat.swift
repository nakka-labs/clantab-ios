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
}
