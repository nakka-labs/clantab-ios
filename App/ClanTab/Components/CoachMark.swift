import ClanTabKit
import SwiftUI

/// One-time contextual coach marks (`CHECKLIST.md` "One-time contextual
/// coach marks") — attach `.coachMark(id:text:edge:)` to whatever view a tip
/// should point at. Shows a small dismissible callout the first time that
/// view appears, once per `id`, then never again on this device unless the
/// store is reset (`CoachMarkStoring.resetAll`, Settings "Show tips again").
///
/// The store rides in via `\.coachMarks` (mirrors `\.avatarImageLoader`) —
/// set once on `RootView`'s top-level content — rather than threaded through
/// every intermediate view's `init`, since a tip can live arbitrarily deep in
/// the view tree it's meant to explain. A `nil` environment (a preview, or a
/// host that never set one) is a silent no-op: never shows anything.
private struct CoachMarkKey: EnvironmentKey {
    static let defaultValue: CoachMarkStoring? = nil
}

extension EnvironmentValues {
    var coachMarks: CoachMarkStoring? {
        get { self[CoachMarkKey.self] }
        set { self[CoachMarkKey.self] = newValue }
    }
}

/// The callout bubble itself — tap anywhere on it to dismiss.
private struct CoachMarkBubble: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                Text(text)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 260)
            .background(Color.accentColor, in: Capsule())
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
    }
}

private struct CoachMarkModifier: ViewModifier {
    let id: String
    let text: String
    let edge: Edge
    @Environment(\.coachMarks) private var store

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .top ? .top : .bottom) {
                if isVisible {
                    CoachMarkBubble(text: text, onDismiss: dismiss)
                        .offset(y: edge == .top ? -44 : 44)
                        .transition(.opacity.combined(with: .move(edge: edge)))
                        .zIndex(1)
                }
            }
            .onAppear {
                guard let store, !store.hasSeen(id) else { return }
                // A short delay so the tip appears once the screen has
                // actually settled, not mid-transition.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        isVisible = true
                    }
                }
            }
    }

    private func dismiss() {
        store?.markSeen(id)
        withAnimation(.easeOut(duration: 0.15)) { isVisible = false }
    }
}

extension View {
    /// Shows a one-time coach mark bubble anchored above (`.top`) or below
    /// (`.bottom`) this view — see `CoachMarkModifier`.
    func coachMark(id: String, text: String, edge: Edge = .top) -> some View {
        modifier(CoachMarkModifier(id: id, text: text, edge: edge))
    }
}
