import Foundation
import Testing
@testable import ClanTabKit

@Suite("UPIPayLink")
struct UPIPayLinkTests {
    @Test("builds a upi://pay link for an INR amount")
    func testINR() throws {
        let url = try #require(UPIPayLink.url(
            vpa: "asha@bank", payeeName: "Asha", amountMinor: 123_45, currency: "INR"
        ))
        let comps = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(comps.scheme == "upi")
        #expect(comps.host == "pay")
        let items = Dictionary(uniqueKeysWithValues: (comps.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(items["pa"] == "asha@bank")
        #expect(items["pn"] == "Asha")
        #expect(items["am"] == "123.45")
        #expect(items["cu"] == "INR")
    }

    @Test("nil for a non-INR currency or a blank VPA")
    func testGuards() {
        #expect(UPIPayLink.url(vpa: "asha@bank", payeeName: "Asha", amountMinor: 100, currency: "USD") == nil)
        #expect(UPIPayLink.url(vpa: nil, payeeName: "Asha", amountMinor: 100, currency: "INR") == nil)
        #expect(UPIPayLink.url(vpa: "", payeeName: "Asha", amountMinor: 100, currency: "INR") == nil)
    }
}
