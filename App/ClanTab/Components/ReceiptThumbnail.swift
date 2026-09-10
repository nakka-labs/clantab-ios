import SwiftUI
import ClanTabKit

/// One receipt photo as a small rounded square (`CHECKLIST.md` "Photo
/// attachment on an expense"), resolved through the shared `AvatarImageLoader`.
/// Tapping it opens `ReceiptViewer` full-screen. An optional `onRemove` adds a
/// delete badge (for the Add/Edit Expense form).
struct ReceiptThumbnail: View {
    let key: String
    /// The group's capability token — needed only for a viewer who isn't a
    /// claimed member.
    var accessToken: String?
    var size: CGFloat = 64
    var onRemove: (() -> Void)?

    @Environment(\.avatarImageLoader) private var loader
    @State private var image: UIImage?
    @State private var showingViewer = false

    var body: some View {
        Button { showingViewer = true } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Surface.well)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: size * 0.34))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain)
                .offset(x: 7, y: -7)
                .accessibilityLabel("Remove receipt")
            }
        }
        .task(id: AvatarTaskID(key: key, generation: loader?.generation ?? 0)) {
            guard let loader else { return }
            if let hit = loader.cached(key) {
                image = hit
            } else {
                image = await loader.load(key, accessToken: accessToken)
            }
        }
        .fullScreenCover(isPresented: $showingViewer) {
            ReceiptViewer(key: key, accessToken: accessToken, initialImage: image)
        }
    }

    private struct AvatarTaskID: Equatable {
        let key: String
        let generation: Int
    }
}

/// Full-screen, pinch-to-zoom view of one receipt.
struct ReceiptViewer: View {
    let key: String
    var accessToken: String?
    var initialImage: UIImage?

    @Environment(\.avatarImageLoader) private var loader
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image ?? initialImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(max(1, scale * pinch))
                    .gesture(
                        MagnificationGesture()
                            .updating($pinch) { value, state, _ in state = value }
                            .onEnded { value in scale = min(6, max(1, scale * value)) }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3)) { scale = scale > 1 ? 1 : 2.5 }
                    }
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding()
            .tint(.white)
        }
        .task {
            if initialImage == nil, let loader {
                image = await loader.load(key, accessToken: accessToken)
            }
        }
    }
}
