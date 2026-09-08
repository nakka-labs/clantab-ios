import Testing
@testable import ClanTabKit

@Suite("MoneyFormat")
struct MoneyFormatTests {
    @Test("plainString formats two decimals")
    func testPlainStringFormatsTwoDecimals() {
        #expect(MoneyFormat.plainString(minorUnits: 1234) == "12.34")
        #expect(MoneyFormat.plainString(minorUnits: 1200) == "12.00")
        #expect(MoneyFormat.plainString(minorUnits: 5) == "0.05")
        #expect(MoneyFormat.plainString(minorUnits: 0) == "0.00")
        #expect(MoneyFormat.plainString(minorUnits: -750) == "-7.50")
    }

    /// The edit form pre-fills a field with `plainString` and parses it back with
    /// `minorUnits(from:)` — they must round-trip exactly for any amount.
    @Test("plainString round-trips through minorUnits")
    func testPlainStringRoundTripsThroughMinorUnits() {
        for value: Int64 in [0, 1, 5, 99, 100, 101, 1234, 99_999, 1_000_000] {
            #expect(MoneyFormat.minorUnits(from: MoneyFormat.plainString(minorUnits: value)) == value)
        }
    }

    @Test("isRoundAmount is true only for whole-unit amounts, sign aside")
    func testIsRoundAmount() {
        #expect(MoneyFormat.isRoundAmount(minorUnits: 120000))
        #expect(MoneyFormat.isRoundAmount(minorUnits: 0))
        #expect(MoneyFormat.isRoundAmount(minorUnits: -50000))
        #expect(!MoneyFormat.isRoundAmount(minorUnits: 120050))
        #expect(!MoneyFormat.isRoundAmount(minorUnits: 5))
        #expect(!MoneyFormat.isRoundAmount(minorUnits: -1))
    }

    /// A round amount drops its ".00"; a non-round one keeps both places.
    /// Asserted by digit count so it holds regardless of the platform's
    /// currency symbol, grouping, and decimal separator (this suite runs on
    /// Linux CI too).
    @Test("string() shows fraction digits only for a non-round amount")
    func testStringDropsTrailingZeroCents() {
        func digits(_ s: String) -> Int { s.filter(\.isNumber).count }

        // ₹1,200.00 → "1200" (4 digits, no cents); ₹1,200.50 → "120050" (6).
        #expect(digits(MoneyFormat.string(minorUnits: 120000, currency: "INR")) == 4)
        #expect(digits(MoneyFormat.string(minorUnits: 120050, currency: "INR")) == 6)
        // $0.00 → "0"; $0.05 → "005".
        #expect(digits(MoneyFormat.string(minorUnits: 0, currency: "USD")) == 1)
        #expect(digits(MoneyFormat.string(minorUnits: 5, currency: "USD")) == 3)
    }

    /// Grouping is always by threes (`DESIGN_BIBLE.md` §1), never the lakh
    /// grouping an `en_IN` device would otherwise apply. Digit count alone
    /// can't catch that, so check the separators directly — locale-independent.
    @Test("string() groups by threes regardless of device locale")
    func testStringGroupsByThrees() {
        // ₹10,00,000.00 under lakh grouping; ₹1,000,000 grouped by threes.
        let lakh = MoneyFormat.string(minorUnits: 100_000_000, currency: "INR")
        #expect(lakh.contains("1,000,000"))
        #expect(!lakh.contains("10,00,000"))
    }

    #if canImport(Darwin)
    /// The exact user-visible strings on Apple platforms (where the pre-push
    /// hook runs); `NumberFormatter`'s currency output is less predictable on
    /// Linux, so this one is Darwin-only.
    @Test("string() renders the expected currency strings on Apple platforms")
    func testStringExactOnApplePlatforms() {
        #expect(MoneyFormat.string(minorUnits: 120000, currency: "INR") == "₹1,200")
        #expect(MoneyFormat.string(minorUnits: 120050, currency: "INR") == "₹1,200.50")
        #expect(MoneyFormat.string(minorUnits: 500, currency: "USD") == "$5")
        #expect(MoneyFormat.string(minorUnits: 5, currency: "USD") == "$0.05")
        #expect(MoneyFormat.string(minorUnits: -50000, currency: "INR") == "-₹500")
        #expect(MoneyFormat.string(minorUnits: 10_000_000, currency: "INR") == "₹100,000")
    }
    #endif
}
