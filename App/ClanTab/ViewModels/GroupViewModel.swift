import Foundation
import Observation
import ClanTabKit

/// Drives Group Home: fetch-on-load / refetch-after-write per `DESIGN.md` §7 —
/// no optimistic UI, no WebSocket in v1 — plus a lightweight foreground poll
/// (`autoRefetch()`, driven by `GroupHomeView`) so a second device's changes
/// show up without a manual pull-to-refresh. Balances and the simplified
/// settle-up list always come from the server's `GroupStateResponse`, never
/// recomputed client-side, so there's exactly one source of truth.
@MainActor
@Observable
final class GroupViewModel {
    /// How often `GroupHomeView` calls `autoRefetch()` while it's foregrounded.
    static let pollInterval: Duration = .seconds(5)

    let groupId: String
    private let client: ClanTabClient
    private let identityStore: IdentityStoring

    private(set) var state: GroupStateResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    /// Set when the server says this group doesn't exist (a 404 on its
    /// capability URL) — the pointer to it is stale and Group Home can never
    /// load. `RootView` watches this to bounce back to the start screen.
    private(set) var groupUnavailable = false

    init(groupId: String, client: ClanTabClient, identityStore: IdentityStoring) {
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

    /// Silent background refresh for the foreground poll and app-foreground
    /// events. Unlike `refetch()` it never shows the loading spinner, and a
    /// transient failure leaves the last good `state` and any existing
    /// `errorMessage` untouched — only a definitive 404 still flips
    /// `groupUnavailable` (so a deleted group is caught even without a manual
    /// refresh). A successful poll clears a stale error banner.
    func autoRefetch() async {
        guard !isLoading else { return }
        do {
            state = try await client.fetchGroupState(groupId: groupId)
            errorMessage = nil
        } catch {
            if Self.isGroupNotFound(error) {
                errorMessage = friendlyMessage(for: error)
                groupUnavailable = true
            }
        }
    }

    /// A 404 for the group itself (`DESIGN.md` §2) — either a bare 404
    /// (`ClanTabClientError.notFound`) or the structured `GROUP_NOT_FOUND`
    /// envelope — as opposed to any other network or decoding failure.
    nonisolated static func isGroupNotFound(_ error: Error) -> Bool {
        switch error as? ClanTabClientError {
        case .notFound:
            return true
        case .server(let code, _):
            return code == "GROUP_NOT_FOUND"
        default:
            return false
        }
    }
}
