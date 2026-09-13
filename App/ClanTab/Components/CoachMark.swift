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
///
/// Caps its own text scaling at `.accessibility1` (`CHECKLIST.md` "UI audit,
/// fresh eyes pass" — critical finding: at the largest system text size this
/// bubble measured 563pt tall, more than half the screen, hiding the very
/// content it was explaining). A supplementary one-time hint doesn't need to
/// track the full accessibility range the way primary content must — capping
/// it keeps the bubble to a few short lines at any system setting, while
/// still growing noticeably for a user who has turned text size up.
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
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

/// Clearance between the bubble and the view it's pointing at.
private let coachMarkGap: CGFloat = 12

/// One visible coach mark's data, published up via `CoachMarkAnchorKey` from
/// wherever `.coachMark` is attached to a rendering host that draws it —
/// see that key's doc comment for why this indirection exists at all.
private struct CoachMarkAnchor: @unchecked Sendable {
    let anchor: Anchor<CGRect>
    let edge: Edge
    let text: String
    let dismiss: () -> Void
}

/// Bubbles a visible coach mark's anchor rect up to whichever ancestor calls
/// `.coachMarkOverlayHost()` (round-3 playtest, 2026-09-13 — a coach mark
/// attached directly to a `List`/`Form` row via `.overlay` got clipped to
/// that row's own bounds, since List rows clip their content; two of the
/// three shipped coach marks live on exactly such a row). An anchor
/// preference isn't affected by any clipping between where it's read and
/// where it's declared, so resolving it at the host — an overlay on the
/// *screen's* own body, a sibling layer to every row rather than nested
/// inside one — draws the bubble unclipped regardless of where the tip
/// itself lives.
private struct CoachMarkAnchorKey: PreferenceKey {
    static let defaultValue: [String: CoachMarkAnchor] = [:]
    static func reduce(value: inout [String: CoachMarkAnchor], nextValue: () -> [String: CoachMarkAnchor]) {
        value.merge(nextValue()) { _, new in new }
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
            .anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) { anchor in
                isVisible ? [id: CoachMarkAnchor(anchor: anchor, edge: edge, text: text, dismiss: dismiss)] : [:]
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
    /// (`.bottom`) this view — see `CoachMarkModifier`. The bubble itself
    /// only actually renders wherever the nearest ancestor's
    /// `.coachMarkOverlayHost()` is — this just marks the anchor and starts
    /// the one-time show/dismiss lifecycle.
    func coachMark(id: String, text: String, edge: Edge = .top) -> some View {
        modifier(CoachMarkModifier(id: id, text: text, edge: edge))
    }

    /// Draws every currently-visible coach mark bubble anchored anywhere in
    /// this view's subtree, as an overlay on `self` rather than nested
    /// inside whatever `List`/`Form` row the tip itself points at — see
    /// `CoachMarkAnchorKey`. Attach once per screen, at the same level as
    /// that screen's own top-level content (outside/after its `List`, not
    /// on a row within it).
    func coachMarkOverlayHost() -> some View {
        overlayPreferenceValue(CoachMarkAnchorKey.self) { anchors in
            GeometryReader { proxy in
                ForEach(Array(anchors.keys), id: \.self) { id in
                    if let mark = anchors[id] {
                        let rect = proxy[mark.anchor]
                        Color.clear
                            .frame(width: rect.width, height: rect.height)
                            .position(x: rect.midX, y: rect.midY)
                            // Only the bubble itself (a `Button`) should
                            // intercept taps — this proxy just positions it,
                            // and must never shadow the real anchor row
                            // underneath (its own tap/swipe actions still
                            // need to work while a coach mark is showing).
                            .allowsHitTesting(false)
                            .overlay(alignment: mark.edge == .top ? .top : .bottom) {
                                CoachMarkBubble(text: mark.text, onDismiss: mark.dismiss)
                                    // Measures the bubble's *own* height each
                                    // time, so it clears the anchor by exactly
                                    // `coachMarkGap` regardless of how many
                                    // lines the text wraps to (`CHECKLIST.md`
                                    // "UI audit, fresh eyes pass").
                                    .alignmentGuide(mark.edge == .top ? .top : .bottom) { d in
                                        mark.edge == .top ? d[.bottom] + coachMarkGap : d[.top] - coachMarkGap
                                    }
                                    .transition(.opacity.combined(with: .move(edge: mark.edge)))
                            }
                    }
                }
            }
        }
    }
}
