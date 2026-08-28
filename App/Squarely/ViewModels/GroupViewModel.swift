import Foundation
import Observation
import SquareKit

/// Drives Group Home: fetch-on-load / refetch-after-write, the whole sync model
/// per `DESIGN.md` §7 — no optimistic UI, no WebSocket in v1. Balances and the
/// simplified settle-up list always come from the server's `GroupStateResponse`,
/// never recomputed client-side, so there's exactly one source of truth.
@MainActor
@Observable
final class GroupViewModel {
    let groupId: String
    private let client: SquarelyClient
    private let identityStore: IdentityStoring

    private(set) var state: GroupStateResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Set when the server says this group doesn't exist (a 404 on its
    /// capability URL) — the pointer to it is stale and Group Home can never
    /// load. `RootView` watches this to bounce back to the start screen.
    private(set) var groupUnavailable = false

    init(groupId: String, client: SquarelyClient, identityStore: IdentityStoring) {
        self.groupId = groupId
        self.client = client
        self.identityStore = identityStore
    }

    var myIdentity: GroupIdentity? {
        identityStore.identity(forGroup: groupId)
    }

    var myBalance: Balance? {
        guard let me = myIdentity else { return nil }
        return state?.balances.first { $0.memberId == me.memberId }
    }

    /// Fetches once per view lifetime; call `refetch()` explicitly after a
    /// mutation or pull-to-refresh.
    func load() async {
        guard state == nil else { return }
        await refetch()
    }

    func refetch() async {
        isLoading = true
        errorMessage = nil
        do {
            state = try await client.fetchGroupState(groupId: groupId)
        } catch {
            errorMessage = friendlyMessage(for: error)
            if Self.isGroupNotFound(error) {
                groupUnavailable = true
            }
        }
        isLoading = false
    }

    /// A 404 for the group itself (`DESIGN.md` §2) — either a bare 404
    /// (`SquarelyClientError.notFound`) or the structured `GROUP_NOT_FOUND`
    /// envelope — as opposed to any other network or decoding failure.
    nonisolated static func isGroupNotFound(_ error: Error) -> Bool {
        switch error as? SquarelyClientError {
        case .notFound:
            return true
        case .server(let code, _):
            return code == "GROUP_NOT_FOUND"
        default:
            return false
        }
    }
}
