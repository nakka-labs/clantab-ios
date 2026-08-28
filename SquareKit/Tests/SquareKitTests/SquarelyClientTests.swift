import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SquareKit

@Suite("SquarelyClient")
struct SquarelyClientTests {
    let baseURL = URL(string: "https://squarely.example.com/")!

    private func decodeBody(_ request: URLRequest?) -> [String: Any] {
        guard let data = request?.httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    @Test("createGroup posts to /api/groups and decodes a 201 response")
    func testCreateGroupSuccess() async throws {
        let responseBody = jsonData([
            "groupId": "g123",
            "joinCode": "K7M9P2",
            "member": ["id": "m1", "displayName": "Alice"],
            "group": ["name": "Goa Trip", "currency": "INR", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2"],
        ])
        let transport = FakeTransport(statusCode: 201, body: responseBody)
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        let response = try await client.createGroup(
            CreateGroupRequest(name: "Goa Trip", currency: "INR", creatorDisplayName: "Alice")
        )

        #expect(response.groupId == "g123")
        #expect(response.joinCode == "K7M9P2")
        #expect(response.member == Member(id: "m1", displayName: "Alice"))
        #expect(response.group.currency == "INR")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://squarely.example.com/api/groups")
        let body = decodeBody(request)
        #expect(body["creatorDisplayName"] as? String == "Alice")
    }

    @Test("resolveJoinCode decodes groupId on success")
    func testResolveJoinCodeSuccess() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData(["groupId": "g123"]))
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        let response = try await client.resolveJoinCode("K7M9P2")
        #expect(response.groupId == "g123")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "https://squarely.example.com/api/groups/resolve/K7M9P2")
    }

    @Test("resolveJoinCode surfaces a bare 404 as .notFound")
    func testResolveJoinCodeNotFound() async {
        let transport = FakeTransport(statusCode: 404, body: Data())
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        await #expect(throws: SquarelyClientError.notFound) {
            _ = try await client.resolveJoinCode("BADCOD")
        }
    }

    @Test("A structured error envelope is surfaced as .server(code:message:)")
    func testStructuredErrorEnvelope() async {
        let errorBody = jsonData(["error": ["code": "SPLIT_MISMATCH", "message": "Splits must sum to the expense amount."]])
        let transport = FakeTransport(statusCode: 400, body: errorBody)
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        await #expect(throws: SquarelyClientError.server(code: "SPLIT_MISMATCH", message: "Splits must sum to the expense amount.")) {
            _ = try await client.addExpense(
                groupId: "g1",
                AddExpenseRequest(
                    payerId: "m1",
                    amountMinor: 100,
                    description: "Snacks",
                    date: Date(timeIntervalSince1970: 0),
                    splitType: .equal,
                    splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
                )
            )
        }
    }

    @Test("A 2xx response that doesn't decode surfaces .decodingFailed")
    func testDecodingFailureOnMalformedBody() async {
        let transport = FakeTransport(statusCode: 200, body: jsonData(["unexpected": "shape"]))
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        do {
            _ = try await client.resolveJoinCode("K7M9P2")
            Issue.record("Expected decodingFailed to be thrown")
        } catch SquarelyClientError.decodingFailed {
            // expected
        } catch {
            Issue.record("Expected .decodingFailed, got \(error)")
        }
    }

    @Test("addExpense omits the id key entirely when none is provided")
    func testAddExpenseOmitsNilId() async throws {
        let transport = FakeTransport(statusCode: 201, body: jsonData([
            "expense": [
                "id": "server-assigned",
                "payerId": "m1",
                "amountMinor": 100,
                "description": "Snacks",
                "date": "2026-01-15T10:00:00Z",
                "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ]))
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        _ = try await client.addExpense(
            groupId: "g1",
            AddExpenseRequest(
                payerId: "m1",
                amountMinor: 100,
                description: "Snacks",
                date: Date(timeIntervalSince1970: 0),
                splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
            )
        )

        let body = decodeBody(await transport.lastRequest)
        #expect(body["id"] == nil)
    }

    @Test("addExpense includes the id key when the client generates one")
    func testAddExpenseIncludesProvidedId() async throws {
        let transport = FakeTransport(statusCode: 201, body: jsonData([
            "expense": [
                "id": "client-generated",
                "payerId": "m1",
                "amountMinor": 100,
                "description": "Snacks",
                "date": "2026-01-15T10:00:00Z",
                "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ]))
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        _ = try await client.addExpense(
            groupId: "g1",
            AddExpenseRequest(
                id: "client-generated",
                payerId: "m1",
                amountMinor: 100,
                description: "Snacks",
                date: Date(timeIntervalSince1970: 0),
                splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
            )
        )

        let body = decodeBody(await transport.lastRequest)
        #expect(body["id"] as? String == "client-generated")
    }

    @Test("fetchGroupState decodes the full group snapshot, including nested balances")
    func testFetchGroupStateDecodesFullSnapshot() async throws {
        let responseBody = jsonData([
            "group": ["name": "Goa Trip", "currency": "INR", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2"],
            "members": [
                ["id": "m1", "displayName": "Alice"],
                ["id": "m2", "displayName": "Bob"],
            ],
            "expenses": [
                [
                    "id": "e1",
                    "payerId": "m1",
                    "amountMinor": 200,
                    "description": "Dinner",
                    "date": "2026-01-15T20:00:00Z",
                    "splitType": "equal",
                    "splits": [
                        ["memberId": "m1", "amountMinor": 100],
                        ["memberId": "m2", "amountMinor": 100],
                    ],
                ],
            ],
            "settlements": [] as [Any],
            "balances": [
                ["memberId": "m1", "netMinor": 100],
                ["memberId": "m2", "netMinor": -100],
            ],
            "simplifiedSettlements": [
                ["fromId": "m2", "toId": "m1", "amountMinor": 100],
            ],
        ])
        let transport = FakeTransport(statusCode: 200, body: responseBody)
        let client = SquarelyClient(baseURL: baseURL, transport: transport)

        let state = try await client.fetchGroupState(groupId: "g1")

        #expect(state.group.name == "Goa Trip")
        #expect(state.group.joinCode == "K7M9P2")
        #expect(state.members.count == 2)
        #expect(state.expenses.first?.splits.count == 2)
        #expect(state.balances == [
            Balance(memberId: "m1", netMinor: 100),
            Balance(memberId: "m2", netMinor: -100),
        ])
        #expect(state.simplifiedSettlements == [
            SimplifiedSettlement(fromId: "m2", toId: "m1", amountMinor: 100),
        ])

        let request = await transport.lastRequest
        #expect(request?.url?.absoluteString == "https://squarely.example.com/api/groups/g1")
    }
}
