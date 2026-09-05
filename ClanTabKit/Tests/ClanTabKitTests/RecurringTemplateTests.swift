import Testing
import Foundation
@testable import ClanTabKit

@Suite("RecurringTemplate")
struct RecurringTemplateTests {
    private func template(
        payerId: String = "m1",
        cadence: RecurringTemplate.Cadence = .monthly,
        cadenceAnchor: Int = 1
    ) -> RecurringTemplate {
        RecurringTemplate(
            id: "t1",
            groupId: "g1",
            description: "Rent",
            amountMinor: 50000,
            currency: "INR",
            payerId: payerId,
            cadence: cadence,
            cadenceAnchor: cadenceAnchor
        )
    }

    // MARK: - RecurringTemplateValidation

    @Test("valid when the payer is still a current member")
    func testValidWhenPayerIsAMember() {
        let members = [Member(id: "m1", displayName: "Ana"), Member(id: "m2", displayName: "Ben")]
        #expect(RecurringTemplateValidation.validity(of: template(payerId: "m1"), members: members) == .valid)
    }

    @Test("payerNoLongerAMember once the payer's been removed from the group")
    func testInvalidWhenPayerRemoved() {
        let members = [Member(id: "m2", displayName: "Ben")]
        #expect(RecurringTemplateValidation.validity(of: template(payerId: "m1"), members: members) == .payerNoLongerAMember)
    }

    // MARK: - RecurringSchedule

    @Test("monthly nextFireDate lands on the anchor day at 9 AM, strictly after now")
    func testMonthlyNextFireDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 10))!

        let next = RecurringSchedule.nextFireDate(for: template(cadence: .monthly, cadenceAnchor: 1), after: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 4, day: 1, hour: 9))!
        #expect(next == expected)
    }

    @Test("weekly nextFireDate lands on the anchor weekday at 9 AM, strictly after now")
    func testWeeklyNextFireDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // 2026-03-15 is a Sunday (weekday 1); anchor is Wednesday (weekday 4).
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 10))!

        let next = RecurringSchedule.nextFireDate(for: template(cadence: .weekly, cadenceAnchor: 4), after: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 3, day: 18, hour: 9))!
        #expect(next == expected)
    }

    @Test("dateComponents matches the cadence's own field, with a fixed 9 AM fire time")
    func testDateComponentsShape() {
        let monthly = RecurringSchedule.dateComponents(for: template(cadence: .monthly, cadenceAnchor: 5))
        #expect(monthly.day == 5)
        #expect(monthly.weekday == nil)
        #expect(monthly.hour == 9)

        let weekly = RecurringSchedule.dateComponents(for: template(cadence: .weekly, cadenceAnchor: 2))
        #expect(weekly.weekday == 2)
        #expect(weekly.day == nil)
    }

    // MARK: - RecurringTemplatesStoring

    @Test("InMemoryRecurringTemplatesStore saves, updates, filters by group, and removes")
    func testInMemoryStore() {
        let store = InMemoryRecurringTemplatesStore()
        store.save(template())
        store.save(RecurringTemplate(id: "t2", groupId: "g2", description: "Other group", amountMinor: 100, currency: "INR", payerId: "m1", cadence: .weekly, cadenceAnchor: 1))

        #expect(store.all(forGroup: "g1").map(\.id) == ["t1"])
        #expect(store.all(forGroup: "g2").map(\.id) == ["t2"])

        var updated = template()
        updated.amountMinor = 60000
        store.save(updated)
        #expect(store.all(forGroup: "g1").first?.amountMinor == 60000)

        store.remove(id: "t1")
        #expect(store.all(forGroup: "g1").isEmpty)
    }

    @Test("UserDefaults-backed store round-trips through a real suite")
    func testUserDefaultsRoundTrip() throws {
        let suiteName = "com.clantab.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsRecurringTemplatesStore(defaults: defaults)
        store.save(template())

        let reloaded = UserDefaultsRecurringTemplatesStore(defaults: defaults)
        #expect(reloaded.all(forGroup: "g1").map(\.id) == ["t1"])

        reloaded.remove(id: "t1")
        #expect(UserDefaultsRecurringTemplatesStore(defaults: defaults).all(forGroup: "g1").isEmpty)
    }
}
