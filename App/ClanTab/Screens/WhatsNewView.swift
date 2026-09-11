import SwiftUI
import ClanTabKit

/// The "What's New" sheet (`CHECKLIST.md` "'What's New' sheet, versioned") —
/// shown to a returning user once per build that shipped something worth
/// telling them about (`WhatsNew.shouldShow`, evaluated by `RootView`).
struct WhatsNewView: View {
    /// Oldest first (`WhatsNew.unseenReleases`'s own order) — reversed below
    /// so the sheet itself reads newest-first, like any changelog.
    let releases: [WhatsNewRelease]
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(releases.reversed()) { release in
                    Section(release.headline) {
                        ForEach(release.items, id: \.self) { item in
                            Label {
                                Text(item)
                            } icon: {
                                Image(systemName: "sparkle").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .navigationTitle("What's New")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
        }
    }
}

#Preview {
    WhatsNewView(
        releases: [
            WhatsNewRelease(
                build: 8,
                headline: "New this update",
                items: [
                    "Friends: see everyone you split with across every group.",
                    "Comment on any expense.",
                    "Split one expense across multiple payers.",
                ]
            ),
        ],
        onDone: {}
    )
}
