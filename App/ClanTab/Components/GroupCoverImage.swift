import SwiftUI
import ClanTabKit

/// A group's cover photo (`CHECKLIST.md` "Group cover image"), resolved through
/// the shared `AvatarImageLoader`. Fills its frame (`scaledToFill`); the caller
/// sets the frame + clip shape. While loading or if the fetch fails it shows a
/// soft wash of the group's accent colour, so there's never a jarring gap — and
/// callers only place this when `coverKey != nil` anyway.
struct GroupCoverImage: View {
    let groupId: String
    let coverKey: String
    /// The group's capability token — only needed when the viewer isn't a
    /// claimed member (rare; a member's session covers it).
    var accessToken: String?

    @Environment(\.avatarImageLoader) private var loader
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            GroupColor.wash(forId: groupId)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .clipped()
        .accessibilityHidden(true)
        .task(id: AvatarTaskID(key: coverKey, generation: loader?.generation ?? 0)) {
            guard let loader else { return }
            if let hit = loader.cached(coverKey) {
                image = hit
            } else {
                let resolved = await loader.load(coverKey, accessToken: accessToken)
                withAnimation(.easeOut(duration: 0.2)) { image = resolved }
            }
        }
    }

    private struct AvatarTaskID: Equatable {
        let key: String
        let generation: Int
    }
}
