import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ClanTabKit

@Suite("ClanTabClient")
struct ClanTabClientTests {
    let baseURL = URL(string: "https://clantab.example.com/")!

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
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.createGroup(
            CreateGroupRequest(name: "Goa Trip", currency: "INR", creatorDisplayName: "Alice")
        )

        #expect(response.groupId == "g123")
        #expect(response.joinCode == "K7M9P2")
        #expect(response.member == Member(id: "m1", displayName: "Alice"))
        #expect(response.group.currency == "INR")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups")
        let body = decodeBody(request)
        #expect(body["creatorDisplayName"] as? String == "Alice")
    }

    @Test("resolveJoinCode decodes groupId on success")
    func testResolveJoinCodeSuccess() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData(["groupId": "g123"]))
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.resolveJoinCode("K7M9P2")
        #expect(response.groupId == "g123")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/resolve/K7M9P2")
    }

    @Test("resolveJoinCode surfaces a bare 404 as .notFound")
    func testResolveJoinCodeNotFound() async {
        let transport = FakeTransport(statusCode: 404, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.notFound) {
            _ = try await client.resolveJoinCode("BADCOD")
        }
    }

    @Test("A structured error envelope is surfaced as .server(code:message:)")
    func testStructuredErrorEnvelope() async {
        let errorBody = jsonData(["error": ["code": "SPLIT_MISMATCH", "message": "Splits must sum to the expense amount."]])
        let transport = FakeTransport(statusCode: 400, body: errorBody)
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "SPLIT_MISMATCH", message: "Splits must sum to the expense amount.")) {
            _ = try await client.addExpense(
                groupId: "g1",
                AddExpenseRequest(
                    payerId: "m1",
                    amountMinor: 100,
                    currency: "USD",
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
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        do {
            _ = try await client.resolveJoinCode("K7M9P2")
            Issue.record("Expected decodingFailed to be thrown")
        } catch ClanTabClientError.decodingFailed {
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
                "currency": "USD",
                "description": "Snacks",
                "date": "2026-01-15T10:00:00Z",
                "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ]))
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        _ = try await client.addExpense(
            groupId: "g1",
            AddExpenseRequest(
                payerId: "m1",
                amountMinor: 100,
                currency: "USD",
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
                "currency": "USD",
                "description": "Snacks",
                "date": "2026-01-15T10:00:00Z",
                "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ]))
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        _ = try await client.addExpense(
            groupId: "g1",
            AddExpenseRequest(
                id: "client-generated",
                payerId: "m1",
                amountMinor: 100,
                currency: "USD",
                description: "Snacks",
                date: Date(timeIntervalSince1970: 0),
                splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
            )
        )

        let body = decodeBody(await transport.lastRequest)
        #expect(body["id"] as? String == "client-generated")
    }

    @Test("addExpense encodes category + categoryIcon when set, omits them when nil")
    func testAddExpenseCategoryEncoding() async throws {
        let response = jsonData([
            "expense": [
                "id": "e1", "payerId": "m1", "amountMinor": 100, "currency": "USD", "description": "Cab",
                "date": "2026-01-15T10:00:00Z", "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ])

        let withCategory = FakeTransport(statusCode: 201, body: response)
        _ = try await ClanTabClient(baseURL: baseURL, transport: withCategory).addExpense(
            groupId: "g1",
            AddExpenseRequest(
                payerId: "m1", amountMinor: 100, currency: "USD", description: "Cab",
                date: Date(timeIntervalSince1970: 0), splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)],
                category: "Transport", categoryIcon: "car"
            )
        )
        let set = decodeBody(await withCategory.lastRequest)
        #expect(set["category"] as? String == "Transport")
        #expect(set["categoryIcon"] as? String == "car")

        let without = FakeTransport(statusCode: 201, body: response)
        _ = try await ClanTabClient(baseURL: baseURL, transport: without).addExpense(
            groupId: "g1",
            AddExpenseRequest(
                payerId: "m1", amountMinor: 100, currency: "USD", description: "Cab",
                date: Date(timeIntervalSince1970: 0), splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
            )
        )
        let unset = decodeBody(await without.lastRequest)
        #expect(unset["category"] == nil)
        #expect(unset["categoryIcon"] == nil)
    }

    @Test("updateGroup PATCHes name + currency and decodes the group summary")
    func testUpdateGroup() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData([
            "group": ["name": "Goa 2.0", "currency": "USD", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2"],
        ]))
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.updateGroup(groupId: "g1", name: "Goa 2.0", currency: "USD")
        #expect(response.group.name == "Goa 2.0")
        #expect(response.group.currency == "USD")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "PATCH")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1")
        let body = decodeBody(request)
        #expect(body["name"] as? String == "Goa 2.0")
        #expect(body["currency"] as? String == "USD")
    }

    @Test("updateGroup omits the key it isn't changing")
    func testUpdateGroupPartial() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData([
            "group": ["name": "Renamed", "currency": "INR", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2"],
        ]))
        _ = try await ClanTabClient(baseURL: baseURL, transport: transport).updateGroup(groupId: "g1", name: "Renamed")
        let body = decodeBody(await transport.lastRequest)
        #expect(body["name"] as? String == "Renamed")
        #expect(body["currency"] == nil)
    }

    @Test("renameMember PATCHes and removeMember DELETEs the member path")
    func testMemberRenameRemove() async throws {
        let rename = FakeTransport(statusCode: 200, body: jsonData(["member": ["id": "m2", "displayName": "Benjamin"]]))
        let renamed = try await ClanTabClient(baseURL: baseURL, transport: rename).renameMember(groupId: "g1", memberId: "m2", displayName: "Benjamin")
        #expect(renamed.member == Member(id: "m2", displayName: "Benjamin"))
        #expect(await rename.lastRequest?.httpMethod == "PATCH")
        #expect(await rename.lastRequest?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/members/m2")

        let remove = FakeTransport(statusCode: 204, body: Data())
        try await ClanTabClient(baseURL: baseURL, transport: remove).removeMember(groupId: "g1", memberId: "m2")
        #expect(await remove.lastRequest?.httpMethod == "DELETE")
    }

    @Test("removing a member in use surfaces .server(MEMBER_IN_USE)")
    func testRemoveMemberInUse() async {
        let transport = FakeTransport(
            statusCode: 409,
            body: jsonData(["error": ["code": "MEMBER_IN_USE", "message": "This member is on expenses or settlements."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)
        await #expect(throws: ClanTabClientError.server(code: "MEMBER_IN_USE", message: "This member is on expenses or settlements.")) {
            try await client.removeMember(groupId: "g1", memberId: "m2")
        }
    }

    @Test("updateExpense PUTs to the id path and decodes the replaced expense")
    func testUpdateExpense() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData([
            "expense": [
                "id": "e1", "payerId": "m2", "amountMinor": 900, "currency": "INR", "description": "Lunch (fixed)",
                "date": "2026-01-02T10:00:00Z", "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 450], ["memberId": "m2", "amountMinor": 450]],
            ],
        ]))
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.updateExpense(
            groupId: "g1", expenseId: "e1",
            AddExpenseRequest(
                payerId: "m2", amountMinor: 900, currency: "INR", description: "Lunch (fixed)",
                date: Date(timeIntervalSince1970: 0), splitType: .equal,
                splits: [ExpenseSplit(memberId: "m1", amountMinor: 450), ExpenseSplit(memberId: "m2", amountMinor: 450)]
            )
        )
        #expect(response.expense.description == "Lunch (fixed)")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/expenses/e1")
        #expect(decodeBody(request)["id"] == nil) // id lives in the path, never the body
    }

    @Test("deleteExpense sends a DELETE and tolerates a 204")
    func testDeleteExpense() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.deleteExpense(groupId: "g1", expenseId: "e1")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/expenses/e1")
    }

    @Test("deleteExpense appends deletedBy and accessToken as query params together")
    func testDeleteExpenseCarriesDeletedByAndToken() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.deleteExpense(groupId: "g1", expenseId: "e1", accessToken: "tok1", deletedBy: "m2")

        let url = await transport.lastRequest?.url
        let query = Set(URLComponents(url: url!, resolvingAgainstBaseURL: false)!.queryItems!)
        #expect(query == [URLQueryItem(name: "token", value: "tok1"), URLQueryItem(name: "deletedBy", value: "m2")])
    }

    @Test("restoreExpense POSTs to the restore path and decodes the expense")
    func testRestoreExpense() async throws {
        let responseBody = jsonData([
            "expense": [
                "id": "e1", "payerId": "m1", "amountMinor": 100, "currency": "INR",
                "description": "x", "date": "2026-01-01T00:00:00Z", "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
            ],
        ])
        let transport = FakeTransport(statusCode: 200, body: responseBody)
        let response = try await ClanTabClient(baseURL: baseURL, transport: transport)
            .restoreExpense(groupId: "g1", expenseId: "e1", accessToken: "tok1")

        #expect(response.expense.id == "e1")
        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/expenses/e1/restore?token=tok1")
    }

    @Test("trash decodes both soft-deleted expenses and settlements, incl. deletedAt/deletedBy")
    func testTrash() async throws {
        let responseBody = jsonData([
            "expenses": [[
                "id": "e1", "payerId": "m1", "amountMinor": 100, "currency": "INR",
                "description": "x", "date": "2026-01-01T00:00:00Z", "splitType": "equal",
                "splits": [["memberId": "m1", "amountMinor": 100]],
                "deletedAt": "2026-01-02T00:00:00Z", "deletedBy": "m2",
            ]],
            "settlements": [] as [Any],
        ])
        let transport = FakeTransport(statusCode: 200, body: responseBody)
        let response = try await ClanTabClient(baseURL: baseURL, transport: transport).trash(groupId: "g1")

        #expect(response.expenses.count == 1)
        #expect(response.expenses[0].deletedBy == "m2")
        #expect(response.expenses[0].deletedAt != nil)
        #expect(response.settlements.isEmpty)
    }

    @Test("a PUT to an unknown expense surfaces .server(NOT_FOUND)")
    func testUpdateExpenseNotFound() async {
        let transport = FakeTransport(
            statusCode: 404,
            body: jsonData(["error": ["code": "NOT_FOUND", "message": "Expense \"e9\" is not in this group."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "NOT_FOUND", message: "Expense \"e9\" is not in this group.")) {
            _ = try await client.updateExpense(
                groupId: "g1", expenseId: "e9",
                AddExpenseRequest(
                    payerId: "m1", amountMinor: 100, currency: "INR", description: "x",
                    date: Date(timeIntervalSince1970: 0), splitType: .equal,
                    splits: [ExpenseSplit(memberId: "m1", amountMinor: 100)]
                )
            )
        }
    }

    @Test("updateSettlement / deleteSettlement hit the id path")
    func testSettlementEditDelete() async throws {
        let put = FakeTransport(statusCode: 200, body: jsonData([
            "settlement": ["id": "s1", "fromId": "m2", "toId": "m1", "amountMinor": 500, "currency": "INR", "date": "2026-01-01T10:00:00Z"],
        ]))
        _ = try await ClanTabClient(baseURL: baseURL, transport: put).updateSettlement(
            groupId: "g1", settlementId: "s1",
            AddSettlementRequest(fromId: "m2", toId: "m1", amountMinor: 500, currency: "INR")
        )
        #expect(await put.lastRequest?.httpMethod == "PUT")
        #expect(await put.lastRequest?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/settlements/s1")

        let del = FakeTransport(statusCode: 204, body: Data())
        try await ClanTabClient(baseURL: baseURL, transport: del).deleteSettlement(groupId: "g1", settlementId: "s1")
        #expect(await del.lastRequest?.httpMethod == "DELETE")
        #expect(await del.lastRequest?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/settlements/s1")
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
                    "currency": "INR",
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
                ["memberId": "m1", "currency": "INR", "netMinor": 100],
                ["memberId": "m2", "currency": "INR", "netMinor": -100],
            ],
            "simplifiedSettlements": [
                ["fromId": "m2", "toId": "m1", "amountMinor": 100, "currency": "INR"],
            ],
        ])
        let transport = FakeTransport(statusCode: 200, body: responseBody)
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let state = try await client.fetchGroupState(groupId: "g1")

        #expect(state.group.name == "Goa Trip")
        #expect(state.group.joinCode == "K7M9P2")
        #expect(state.members.count == 2)
        #expect(state.expenses.first?.splits.count == 2)
        #expect(state.balances == [
            Balance(memberId: "m1", currency: "INR", netMinor: 100),
            Balance(memberId: "m2", currency: "INR", netMinor: -100),
        ])
        #expect(state.simplifiedSettlements == [
            SimplifiedSettlement(fromId: "m2", toId: "m1", amountMinor: 100, currency: "INR"),
        ])

        let request = await transport.lastRequest
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1")
    }

    // MARK: - Access token (ACCESS_TOKEN_PLAN.md)

    @Test("fetchGroupState appends ?token= when an accessToken is given, omits it entirely otherwise")
    func testFetchGroupStateCarriesAccessToken() async throws {
        let responseBody = jsonData([
            "group": ["name": "Goa Trip", "currency": "INR", "createdAt": "2026-01-15T10:00:00Z", "joinCode": "K7M9P2", "accessToken": "tok123"],
            "members": [] as [Any], "expenses": [] as [Any], "settlements": [] as [Any],
            "balances": [] as [Any], "simplifiedSettlements": [] as [Any],
        ])
        let withToken = FakeTransport(statusCode: 200, body: responseBody)
        let state = try await ClanTabClient(baseURL: baseURL, transport: withToken)
            .fetchGroupState(groupId: "g1", accessToken: "tok123")
        #expect(state.group.accessToken == "tok123")
        let requestURL = await withToken.lastRequest?.url?.absoluteString
        #expect(requestURL == "https://clantab.example.com/api/groups/g1?token=tok123")

        let withoutToken = FakeTransport(statusCode: 200, body: responseBody)
        _ = try await ClanTabClient(baseURL: baseURL, transport: withoutToken).fetchGroupState(groupId: "g1")
        let bareURL = await withoutToken.lastRequest?.url?.absoluteString
        #expect(bareURL == "https://clantab.example.com/api/groups/g1")
    }

    @Test("resolveJoinCode decodes the current accessToken alongside groupId")
    func testResolveJoinCodeDecodesAccessToken() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData(["groupId": "g123", "accessToken": "tok456"]))
        let response = try await ClanTabClient(baseURL: baseURL, transport: transport).resolveJoinCode("K7M9P2")
        #expect(response.groupId == "g123")
        #expect(response.accessToken == "tok456")
    }

    @Test("regenerateLink POSTs to the regenerate-link path with the current token, decodes the new one")
    func testRegenerateLink() async throws {
        let transport = FakeTransport(statusCode: 200, body: jsonData(["accessToken": "fresh789"]))
        let response = try await ClanTabClient(baseURL: baseURL, transport: transport)
            .regenerateLink(groupId: "g1", accessToken: "old123")
        #expect(response.accessToken == "fresh789")
        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/regenerate-link?token=old123")
    }
}
