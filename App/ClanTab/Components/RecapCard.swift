import SwiftUI
import ClanTabKit

/// A shareable square-ish card summarising a group — either its settle-up plan
/// or a spending recap (`CHECKLIST.md` "Shareable settle-up / recap card").
/// Rendered off-screen to a PNG via `ImageRenderer` and handed to a
/// `ShareLink`; never shown in the app's own layout. All figures come straight
/// from the values already on screen — nothing is recomputed here.
struct RecapCard: View {
    enum Content {
        /// The server's simplified settle-up plan.
        case settleUp([SimplifiedSettlement])
        /// Total spent in `currency`, plus per-member spend (already sorted).
        case recap(totalMinor: Int64, byMember: [MemberSpend], currency: String)
    }

    let groupName: String
    let groupEmoji: String?
    let members: [Member]
    let content: Content

    /// The canvas the `ImageRenderer` rasterises. 4:5 — the aspect most
    /// messaging and social apps show without cropping.
    static let size = CGSize(width: 1080, height: 1350)

    var body: some View {
        VStack(alignment: .leading, spacing: 40) {
            header
            Spacer(minLength: 24)
            bodyCard
            Spacer(minLength: 24)
            Text("Made with ClanTab")
                .font(.display(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(72)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .background(Self.brandGradient)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(caption)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .tracking(3)
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 16) {
                if let groupEmoji, !groupEmoji.isEmpty {
                    Text(groupEmoji).font(.system(size: 64))
                }
                Text(groupName.isEmpty ? "Your group" : groupName)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
        }
    }

    private var caption: String {
        switch content {
        case .settleUp: return "SETTLE UP"
        case .recap: return "SPENDING RECAP"
        }
    }

    // MARK: - Body

    private var bodyCard: some View {
        VStack(alignment: .leading, spacing: 28) {
            switch content {
            case .settleUp(let settlements):
                settleUpBody(settlements)
            case .recap(let total, let byMember, let currency):
                recapBody(total: total, byMember: byMember, currency: currency)
            }
        }
        .padding(44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
    }

    @ViewBuilder
    private func settleUpBody(_ settlements: [SimplifiedSettlement]) -> some View {
        if settlements.isEmpty {
            VStack(spacing: 16) {
                Text("🎉").font(.system(size: 88))
                Text("Everyone's settled up")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        } else {
            // Cap the list so a big group's card stays legible; the tail is
            // summarised rather than dropped silently.
            let shown = settlements.prefix(7)
            ForEach(Array(shown), id: \.self) { s in
                HStack(spacing: 14) {
                    personChip(name(s.fromId))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.black.opacity(0.35))
                    personChip(name(s.toId))
                    Spacer(minLength: 12)
                    Text(MoneyFormat.string(minorUnits: s.amountMinor, currency: s.currency))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.85))
                }
            }
            if settlements.count > shown.count {
                Text("+ \(settlements.count - shown.count) more")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .foregroundStyle(.black.opacity(0.4))
            }
        }
    }

    @ViewBuilder
    private func recapBody(total: Int64, byMember: [MemberSpend], currency: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Total spent")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.5))
            Text(MoneyFormat.string(minorUnits: total, currency: currency))
                .font(.display(size: 76, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.9))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }

        let spenders = byMember.filter { $0.totalMinor > 0 }.prefix(5)
        ForEach(Array(spenders), id: \.id) { entry in
            let fraction = total > 0 ? Double(entry.totalMinor) / Double(total) : 0
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 14) {
                    personChip(entry.member.displayName)
                    Spacer(minLength: 12)
                    Text(MoneyFormat.string(minorUnits: entry.totalMinor, currency: currency))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.black.opacity(0.8))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.black.opacity(0.08))
                        Capsule().fill(MemberColor.color(for: entry.member.displayName))
                            .frame(width: max(0, geo.size.width * fraction))
                    }
                }
                .frame(height: 10)
            }
        }
    }

    // MARK: - Bits

    /// A member's avatar plus their first name — enough to read the row
    /// without the full name overflowing.
    private func personChip(_ displayName: String) -> some View {
        HStack(spacing: 10) {
            MemberAvatar(name: displayName, size: 44)
            Text(displayName.split(separator: " ").first.map(String.init) ?? displayName)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.8))
                .lineLimit(1)
        }
    }

    private func name(_ memberId: String) -> String {
        members.first { $0.id == memberId }?.displayName ?? "Someone"
    }

    /// `DESIGN_BIBLE.md` §3's one sanctioned gradient — the app's own hue
    /// (250°) at two points on the OKLCH lightness scale, used only for hero
    /// moments like this.
    static let brandGradient = LinearGradient(
        colors: [
            OKLCH.color(hue: 250, lightness: 0.60, chroma: 0.15),
            OKLCH.color(hue: 250, lightness: 0.40, chroma: 0.14),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Rasterise a card to a PNG `Image` on the main actor. `nil` if the
    /// renderer can't produce a bitmap (shouldn't happen for a fixed-size,
    /// dependency-free view, but `ImageRenderer` is failable).
    @MainActor
    static func render(_ card: RecapCard) -> Image? {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let uiImage = renderer.uiImage else { return nil }
        return Image(uiImage: uiImage)
    }
}

extension OKLCH {
    /// SwiftUI `Color` from the shared OKLCH formula — the App-side bridge,
    /// same split as `MemberColor.color(for:)`.
    static func color(hue: Double, lightness: Double, chroma: Double) -> Color {
        let c = sRGB(hue: hue, lightness: lightness, chroma: chroma)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}
