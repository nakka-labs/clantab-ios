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
    /// 25s — same UX for a low-frequency app as the original 5s, but cuts the
    /// Workers request/row-read bill at scale (`SHIP_PLAN.md` Track 3 §8).
    static let pollInterval: Duration = .seconds(25)

    let groupId: String
    private let client: ClanTabClient
    private let auth: AuthViewModel

    private(set) var state: GroupStateResponse?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    /// This group's capability-link credential (`ACCESS_TOKEN_PLAN.md`),
    /// carried alongside `groupId` on every group-data call. Kept in sync
    /// with the server on every successful fetch (`state?.group.accessToken`)
    /// so a rotation from another device — or this one's own "Regenerate
    /// Link" via `updateAccessToken` — is picked up automatically. `nil` for
    /// a group that predates this feature and was never regenerated.
    private(set) var accessToken: String?

    /// Set when the server says this group doesn't exist (a 404 on its
    /// capability URL) — the pointer to it is stale and Group Home can never
    /// load. `RootView` watches this to bounce back to the start screen.
    private(set) var groupUnavailable = false

    init(groupId: String, client: ClanTabClient, auth: AuthViewModel, accessToken: String? = nil) {
        self.groupId = groupId
        self.client = client
        self.auth = auth
        self.accessToken = accessToken
    }

    /// After "Regenerate Link" mints a fresh token — update immediately
    /// (before the caller's next request), rather than waiting on a `refetch()`
    /// that would otherwise still use the now-invalid old one.
    func updateAccessToken(_ token: String) {
        accessToken = token
    }

    /// "Me" in this group — from the signed-in identity's authoritative group
    /// list (`AuthViewModel.groups`), not local storage
    /// (`MANDATORY_LOGIN_PLAN.md` Part 3). `nil` only transiently, before the
    /// first `refreshGroups()` completes or if this membership was never
    /// claimed on this identity.
    var myIdentity: GroupMembershipSummary? {
        auth.groups.first { $0.groupId == groupId }
    }

    /// The current member's net balance in every currency they have activity in
    /// (nonzero only — an empty array means "all settled up").
    var myBalances: [Balance] {
        guard let me = myIdentity else { return [] }
        return balances(forMember: me.memberId)
    }

    func balances(forMember memberId: String) -> [Balance] {
        state?.balances.filter { $0.memberId == memberId } ?? []
    }

    /// Default currency for a new expense: the most recently added expense's
    /// currency, falling back to the group's home currency.
    var lastUsedCurrency: String {
        state?.expenses.last?.currency ?? state?.group.currency ?? AppConfig.supportedCurrencies.first!
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
            state = try await client.fetchGroupState(groupId: groupId, accessToken: accessToken)
            if let fresh = state?.group.accessToken { accessToken = fresh }
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
            state = try await client.fetchGroupState(groupId: groupId, accessToken: accessToken)
            if let fresh = state?.group.accessToken { accessToken = fresh }
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
