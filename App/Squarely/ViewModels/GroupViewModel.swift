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
        }
        isLoading = false
    }
}
