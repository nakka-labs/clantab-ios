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
}
