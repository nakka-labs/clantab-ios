import SwiftUI
import SquareKit

struct RootView: View {
    let client: SquarelyClient
    let identityStore: IdentityStoring

    @AppStorage("squarely.lastGroupId") private var lastGroupId: String = ""
    @State private var route: AppRoute = .start

    var body: some View {
        NavigationStack {
            content
        }
        .task { resolveInitialRoute() }
        .onOpenURL { url in handleDeepLink(url) }
    }

    @ViewBuilder
    private var content: some View {
        switch route {
        case .start:
            StartView(
                onCreate: { route = .createGroup },
                onJoinWithCode: { route = .joinGroup(groupId: nil) }
            )
        case .createGroup:
            CreateGroupView(
                client: client,
                identityStore: identityStore,
                onCreated: enterGroup,
                onCancel: { route = .start }
            )
        case .joinGroup(let groupId):
            JoinGroupView(
                groupId: groupId,
                client: client,
                identityStore: identityStore,
                onJoined: enterGroup,
                onCancel: { route = .start }
            )
        case .group(let groupId):
            GroupHomeView(groupId: groupId, client: client, identityStore: identityStore)
        }
    }

    /// On launch, skip straight back into the last group this device was
    /// active in, as long as we still have a remembered identity for it.
    private func resolveInitialRoute() {
        guard route == .start else { return }
        if !lastGroupId.isEmpty, identityStore.identity(forGroup: lastGroupId) != nil {
            route = .group(groupId: lastGroupId)
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let groupId = Self.extractGroupId(from: url) else { return }
        if identityStore.identity(forGroup: groupId) != nil {
            enterGroup(groupId)
        } else {
            route = .joinGroup(groupId: groupId)
        }
    }

    private func enterGroup(_ groupId: String) {
        lastGroupId = groupId
        route = .group(groupId: groupId)
    }

    /// Recognizes both a real capability link (`https://<host>/g/:groupId`, per
    /// `DESIGN.md` §1) and the `squarely://g/:groupId` scheme registered in
    /// `project.yml` for Simulator testing before a production domain exists.
    static func extractGroupId(from url: URL) -> String? {
        if url.scheme == "squarely", url.host == "g" {
            return url.pathComponents.dropFirst().first
        }
        let components = url.pathComponents.filter { $0 != "/" }
        if let index = components.firstIndex(of: "g"), components.indices.contains(index + 1) {
            return components[index + 1]
        }
        return nil
    }
}
