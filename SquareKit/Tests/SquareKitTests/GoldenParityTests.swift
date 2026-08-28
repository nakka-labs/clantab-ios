import Foundation
import Testing
@testable import SquareKit

/// Runs the language-neutral vectors in `test-fixtures/balances/` through
/// `Balances.compute` + `Simplify.simplify`. The Worker's `worker/test/logic.test.ts`
/// runs the *same* files — so if the Swift and TypeScript implementations ever
/// diverge, one side's CI goes red. See `test-fixtures/README.md`.
@Suite("Golden Parity")
struct GoldenParityTests {

    struct BalanceFixture: Decodable, Sendable {
        let name: String
        let members: [Member]
        let expenses: [Expense]
        let settlements: [Settlement]
        let expectedBalances: [Balance]
        let expectedSimplified: [SimplifiedSettlement]
    }

    @Test("every fixture matches Balances.compute and Simplify.simplify")
    func goldenFixtures() throws {
        let fixtures = try Self.loadFixtures()
        #expect(!fixtures.isEmpty, "no fixtures found under test-fixtures/balances/")

        for fixture in fixtures {
            let balances = Balances.compute(
                members: fixture.members,
                expenses: fixture.expenses,
                settlements: fixture.settlements
            )
            #expect(balances == fixture.expectedBalances, "\(fixture.name): balances")
            #expect(
                Simplify.simplify(balances: balances) == fixture.expectedSimplified,
                "\(fixture.name): simplified plan"
            )
            #expect(
                balances.reduce(Int64(0)) { $0 + $1.netMinor } == 0,
                "\(fixture.name): balances must sum to zero"
            )
        }
    }

    /// `test-fixtures/` lives at the repo root — four levels up from this file
    /// (`SquareKit/Tests/SquareKitTests/`).
    static func loadFixtures() throws -> [BalanceFixture] {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SquareKitTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // SquareKit/
            .deletingLastPathComponent()   // <repo root>/
            .appendingPathComponent("test-fixtures/balances", isDirectory: true)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let files = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        return try files.map { try decoder.decode(BalanceFixture.self, from: Data(contentsOf: $0)) }
    }
}
