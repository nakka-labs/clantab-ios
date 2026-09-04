import Testing
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ClanTabKit

@Suite("ClanTabClient — accounts")
struct ClanTabAuthClientTests {
    let baseURL = URL(string: "https://clantab.example.com/")!

    private func decodeBody(_ request: URLRequest?) -> [String: Any] {
        guard let data = request?.httpBody,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: - sign in

    @Test("signInWithApple posts the identity token and decodes token + groups")
    func testSignInSuccess() async throws {
        let body = jsonData([
            "sessionToken": "sess.tok.en",
            "expiresAt": "2026-10-03T10:00:00Z",
            "groups": [
                ["groupId": "g1", "memberId": "m1", "displayName": "Priya"],
                ["groupId": "g2", "memberId": "m9", "displayName": "Priya"],
            ],
        ])
        let transport = FakeTransport(statusCode: 200, body: body)
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.signInWithApple(identityToken: "apple.jwt.here")

        #expect(response.sessionToken == "sess.tok.en")
        #expect(response.groups?.count == 2)
        #expect(response.groups?.first == GroupMembershipSummary(groupId: "g1", memberId: "m1", displayName: "Priya"))

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/apple")
        #expect(decodeBody(request)["identityToken"] as? String == "apple.jwt.here")
        #expect(decodeBody(request)["authorizationCode"] == nil) // omitted when not provided
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("signInWithApple includes the authorizationCode when given")
    func testSignInWithAuthCode() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["sessionToken": "s", "expiresAt": "2026-10-03T10:00:00Z", "groups": [] as [Any]])
        )
        _ = try await ClanTabClient(baseURL: baseURL, transport: transport)
            .signInWithApple(identityToken: "jwt", authorizationCode: "code-abc")
        #expect(decodeBody(await transport.lastRequest)["authorizationCode"] as? String == "code-abc")
    }

    @Test("an unverifiable Apple token surfaces as .server(INVALID_APPLE_TOKEN)")
    func testSignInRejected() async {
        let transport = FakeTransport(
            statusCode: 401,
            body: jsonData(["error": ["code": "INVALID_APPLE_TOKEN", "message": "Could not verify."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "INVALID_APPLE_TOKEN", message: "Could not verify.")) {
            _ = try await client.signInWithApple(identityToken: "junk")
        }
    }

    // MARK: - refresh

    @Test("refreshSession sends a bodyless bearer POST and decodes a fresh token")
    func testRefresh() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["sessionToken": "fresh.tok.en", "expiresAt": "2026-11-01T00:00:00Z"])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.refreshSession(token: "old.tok.en")
        #expect(response.sessionToken == "fresh.tok.en")
        #expect(response.groups == nil)

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/refresh")
        #expect(request?.httpBody == nil)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer old.tok.en")
    }

    // MARK: - my groups

    @Test("myGroups sends a bearer GET and decodes the list")
    func testMyGroups() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["groups": [["groupId": "g1", "memberId": "m1", "displayName": "Priya"]]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.myGroups(token: "sess.tok.en")
        #expect(response.groups == [GroupMembershipSummary(groupId: "g1", memberId: "m1", displayName: "Priya")])

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "GET")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/groups")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess.tok.en")
    }

    @Test("peopleAcrossGroups decodes the aggregation + per-group edges")
    func testPeopleAcrossGroups() async throws {
        let body = jsonData([
            "people": [[
                "id": "abc123opaque",
                "displayName": "Bob",
                "net": [["currency": "INR", "netMinor": -300]],
                "groups": [
                    [
                        "groupId": "g1", "groupName": "Goa", "currency": "INR",
                        "amountMinor": 500, "youPay": false,
                        "myMemberId": "m1", "theirMemberId": "m2",
                    ],
                    [
                        "groupId": "g2", "groupName": "Flat", "currency": "INR",
                        "amountMinor": 200, "youPay": true,
                        "myMemberId": "m9", "theirMemberId": "m8",
                    ],
                ],
            ]],
        ])
        let transport = FakeTransport(statusCode: 200, body: body)
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.peopleAcrossGroups(token: "sess")

        #expect(response.people.count == 1)
        let bob = response.people[0]
        #expect(bob.id == "abc123opaque")
        #expect(bob.net == [CrossGroupNet(currency: "INR", netMinor: -300)])
        #expect(bob.groups.count == 2)
        #expect(bob.groups[0] == CrossGroupEdge(
            groupId: "g1", groupName: "Goa", currency: "INR", amountMinor: 500,
            youPay: false, myMemberId: "m1", theirMemberId: "m2"
        ))
        #expect(await transport.lastRequest?.url?.absoluteString == "https://clantab.example.com/api/auth/people")
        #expect(await transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
    }

    @Test("an expired session surfaces as .server(INVALID_SESSION)")
    func testMyGroupsExpiredSession() async {
        let transport = FakeTransport(
            statusCode: 401,
            body: jsonData(["error": ["code": "INVALID_SESSION", "message": "Sign in again."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "INVALID_SESSION", message: "Sign in again.")) {
            _ = try await client.myGroups(token: "stale")
        }
    }

    // MARK: - claim

    @Test("claimableMembers sends a bearer GET to the group's claimable route")
    func testClaimable() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["members": [["id": "m1", "displayName": "Priya"], ["id": "m2", "displayName": "Sam"]]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.claimableMembers(groupId: "g1", token: "sess")
        #expect(response.members == [Member(id: "m1", displayName: "Priya"), Member(id: "m2", displayName: "Sam")])

        let request = await transport.lastRequest
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/claimable")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
    }

    @Test("claimMember posts to the memberId path and decodes the linked member")
    func testClaim() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["member": ["id": "m1", "displayName": "Priya"]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let response = try await client.claimMember(groupId: "g1", memberId: "m1", token: "sess")
        #expect(response.member == Member(id: "m1", displayName: "Priya"))

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/groups/g1/members/m1/claim")
        #expect(request?.httpBody == nil)
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
    }

    @Test("a member already linked to someone else surfaces as .server(ALREADY_CLAIMED)")
    func testClaimConflict() async {
        let transport = FakeTransport(
            statusCode: 409,
            body: jsonData(["error": ["code": "ALREADY_CLAIMED", "message": "Linked to another account."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "ALREADY_CLAIMED", message: "Linked to another account.")) {
            _ = try await client.claimMember(groupId: "g1", memberId: "m1", token: "sess")
        }
    }

    // MARK: - delete account

    @Test("deleteAccount sends a bearer DELETE and tolerates a 204 with no body")
    func testDeleteAccount() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.deleteAccount(token: "sess")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/account")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
    }

    @Test("deleteAccount surfaces a server error")
    func testDeleteAccountError() async {
        let transport = FakeTransport(
            statusCode: 401,
            body: jsonData(["error": ["code": "INVALID_SESSION", "message": "Sign in again."]])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        await #expect(throws: ClanTabClientError.server(code: "INVALID_SESSION", message: "Sign in again.")) {
            try await client.deleteAccount(token: "stale")
        }
    }
}
