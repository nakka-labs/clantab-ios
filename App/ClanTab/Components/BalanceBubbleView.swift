import ClanTabKit
import SwiftUI

/// The balance-bubble view (`FEATURE_BACKLOG.md` "Balance bubble/circle-pack
/// view") — each member a circle sized by |their balance|, the biggest one
/// centred, everyone-settled shrunk to a dot. A glance answer to "who owes the
/// most"; the list below is still where "how much do I owe whom" lives. One
/// currency only (the one with the most money moving) — bubbles are never
/// blended across currencies.
struct BalanceBubbleView: View {
    let members: [Member]
    /// The full per-member, per-currency balance set (`GroupStateResponse.balances`).
    let balances: [Balance]

    /// The currency the bubbles are drawn in — whichever has the single
    /// largest-magnitude balance, so the view tracks the real money movement.
    private var currency: String {
        balances.max { abs($0.netMinor) < abs($1.netMinor) }?.currency ?? ""
    }

    private func net(_ memberId: String) -> Int64 {
        balances.first { $0.memberId == memberId && $0.currency == currency }?.netMinor ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let packed = CirclePack.layout(
                members.map { (id: $0.id, weight: Double(abs(net($0.id)))) },
                width: geo.size.width,
                height: geo.size.height,
                minRadius: 11,
                maxRadius: min(geo.size.height, geo.size.width) / 2.6,
                // Any nonzero balance clears the initials threshold below, so a
                // small-but-real debt never reads as an anonymous settled dot.
                minNonZeroRadius: 20
            )
            ZStack {
                ForEach(packed) { circle in
                    bubble(circle)
                        .position(x: circle.x, y: circle.y)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 190)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private func bubble(_ circle: PackedCircle) -> some View {
        let member = members.first { $0.id == circle.id }
        let n = net(circle.id)
        let color = MemberColor.color(for: member?.displayName ?? "")
        let owed = n > 0
        let settled = n == 0

        ZStack {
            Circle()
                .fill(settled ? Color.secondary.opacity(0.22) : (owed ? color.opacity(0.26) : color))
                .overlay {
                    if owed { Circle().strokeBorder(color, lineWidth: 2) }
                }

            if circle.radius >= 19, let member {
                VStack(spacing: 1) {
                    Text(MemberAvatar.initials(from: member.displayName))
                        .font(.system(size: min(circle.radius * 0.5, 16), weight: .semibold, design: .rounded))
                        .foregroundStyle(owed ? color : .white)
                    if circle.radius >= 36 {
                        Text(MoneyFormat.string(minorUnits: abs(n), currency: currency))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle((owed ? color : .white).opacity(0.9))
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(2)
            }
        }
        .frame(width: circle.radius * 2, height: circle.radius * 2)
    }

    private var accessibilitySummary: String {
        let lines = members.compactMap { member -> String? in
            let n = net(member.id)
            guard n != 0 else { return nil }
            let amount = MoneyFormat.string(minorUnits: abs(n), currency: currency)
            return "\(member.displayName) \(n > 0 ? "is owed" : "owes") \(amount)"
        }
        return lines.isEmpty ? "Everyone is settled up" : lines.joined(separator: ", ")
    }
}
