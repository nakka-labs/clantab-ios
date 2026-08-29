import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ClanTabKit

/// A `ClanTabTransport` that never touches the network or the platform's URL
/// loading system — request encoding, response decoding, and error handling are
/// tested purely through this in-memory double, which is both simpler and more
/// portable across platforms than stubbing `URLProtocol`.
actor FakeTransport: ClanTabTransport {
    struct Stubbed {
        let statusCode: Int
        let body: Data
    }

    private var stub: Stubbed
    private(set) var lastRequest: URLRequest?

    init(statusCode: Int = 200, body: Data = Data()) {
        self.stub = Stubbed(statusCode: statusCode, body: body)
    }

    func setStub(statusCode: Int, body: Data) {
        stub = Stubbed(statusCode: statusCode, body: body)
    }

    func send(_ request: URLRequest) async throws -> (data: Data, statusCode: Int) {
        lastRequest = request
        return (stub.body, stub.statusCode)
    }
}

func jsonData(_ object: [String: Any]) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}
