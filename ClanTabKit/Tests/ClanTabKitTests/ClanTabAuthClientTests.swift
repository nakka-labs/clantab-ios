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

    // MARK: - push notifications (FEATURE_BACKLOG.md)

    @Test("registerDevice POSTs the token + platform with a bearer, tolerates a 204")
    func testRegisterDevice() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.registerDevice(deviceToken: "deadbeef", token: "sess")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/devices")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
        #expect(decodeBody(request)["token"] as? String == "deadbeef")
        #expect(decodeBody(request)["platform"] as? String == "ios")
    }

    @Test("registerDevice sends a non-default platform when given")
    func testRegisterDeviceCustomPlatform() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        try await ClanTabClient(baseURL: baseURL, transport: transport)
            .registerDevice(deviceToken: "tok", platform: "ios-sim", token: "sess")
        #expect(decodeBody(await transport.lastRequest)["platform"] as? String == "ios-sim")
    }

    @Test("unregisterDevice DELETEs the token's own path with a bearer")
    func testUnregisterDevice() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.unregisterDevice(deviceToken: "deadbeef", token: "sess")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/devices/deadbeef")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
    }

    // MARK: - image storage (CHECKLIST.md "Profile photos")

    @Test("presignMediaUpload posts the upload body with a bearer and decodes the ticket")
    func testPresignMediaUpload() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData([
                "url": "https://acc.r2.cloudflarestorage.com/clantab-media/avatars/abc?X-Amz-Signature=sig",
                "key": "avatars/abc",
                "method": "PUT",
                "headers": ["Content-Type": "image/jpeg", "Content-Length": "1234"],
            ])
        )
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        let ticket = try await client.presignMediaUpload(
            .avatar, contentType: "image/jpeg", contentLength: 1234, token: "sess"
        )

        #expect(ticket.key == "avatars/abc")
        #expect(ticket.headers["Content-Length"] == "1234")

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "POST")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/media/presign")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")
        let sent = decodeBody(request)
        #expect(sent["operation"] as? String == "upload")
        #expect(sent["purpose"] as? String == "avatar")
        #expect(sent["contentLength"] as? Int == 1234)
        #expect(sent["key"] == nil) // never client-supplied on upload
    }

    @Test("presignMediaUpload threads groupId/expenseId for a receipt")
    func testPresignReceipt() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["url": "https://r2/x", "key": "expenses/g/e/r", "method": "PUT", "headers": [:] as [String: String]])
        )
        _ = try await ClanTabClient(baseURL: baseURL, transport: transport)
            .presignMediaUpload(.receipt, contentType: "image/png", contentLength: 10,
                                groupId: "g1", expenseId: "e1", token: "sess")
        let sent = decodeBody(await transport.lastRequest)
        #expect(sent["groupId"] as? String == "g1")
        #expect(sent["expenseId"] as? String == "e1")
    }

    @Test("presignMediaView posts operation=view with the key")
    func testPresignMediaView() async throws {
        let transport = FakeTransport(
            statusCode: 200,
            body: jsonData(["url": "https://r2/get?sig", "key": "avatars/abc"])
        )
        let view = try await ClanTabClient(baseURL: baseURL, transport: transport)
            .presignMediaView(key: "avatars/abc", token: "sess")

        #expect(view.url.absoluteString == "https://r2/get?sig")
        let sent = decodeBody(await transport.lastRequest)
        #expect(sent["operation"] as? String == "view")
        #expect(sent["key"] as? String == "avatars/abc")
    }

    @Test("uploadImage PUTs the bytes + ticket headers to the presigned URL with no ClanTab auth")
    func testUploadImage() async throws {
        let transport = FakeTransport(statusCode: 200, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)
        let ticket = MediaUploadTicket(
            url: URL(string: "https://acc.r2.cloudflarestorage.com/clantab-media/avatars/abc?sig")!,
            key: "avatars/abc",
            headers: ["Content-Type": "image/jpeg", "Content-Length": "3"]
        )

        try await client.uploadImage(Data([1, 2, 3]), using: ticket)

        let request = await transport.lastRequest
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.host == "acc.r2.cloudflarestorage.com")
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
        #expect(request?.httpBody == Data([1, 2, 3]))
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("uploadImage throws on a non-2xx (R2 signature/size mismatch is a 403)")
    func testUploadImageRejected() async {
        let transport = FakeTransport(statusCode: 403, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)
        let ticket = MediaUploadTicket(url: URL(string: "https://r2/x")!, key: "k", headers: [:])
        await #expect(throws: ClanTabClientError.self) {
            try await client.uploadImage(Data([9]), using: ticket)
        }
    }

    @Test("setAvatar / clearAvatar hit api/auth/avatar with a bearer and tolerate a 204")
    func testSetAndClearAvatar() async throws {
        let transport = FakeTransport(statusCode: 204, body: Data())
        let client = ClanTabClient(baseURL: baseURL, transport: transport)

        try await client.setAvatar(token: "sess")
        var request = await transport.lastRequest
        #expect(request?.httpMethod == "PUT")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/avatar")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer sess")

        try await client.clearAvatar(token: "sess")
        request = await transport.lastRequest
        #expect(request?.httpMethod == "DELETE")
        #expect(request?.url?.absoluteString == "https://clantab.example.com/api/auth/avatar")
    }
}
