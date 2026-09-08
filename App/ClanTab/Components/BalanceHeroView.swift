import SwiftUI
import ClanTabKit

/// The "You are owed ₹1,200" / "You owe ₹350" hero card on Group Home. With
/// multi-currency a member can be owed in one currency and owe in another, so
/// each currency gets its own line and they're never blended.
struct BalanceHeroView: View {
    /// The current member's nonzero balances, one per currency.
    let balances: [Balance]
    /// This group's formula accent (`CHECKLIST.md` "Per-group accent color")
    /// — the card's shadow tint, so the focal card carries the group's
    /// identity. `nil` falls back to a neutral card.
    var accent: Color?
    /// The group's two-stop wash for the card background (`DESIGN_BIBLE.md`
    /// §3 — `GroupColor.wash(forId:)`). `nil` → a flat neutral card.
    var wash: LinearGradient?
    /// The group's state hasn't loaded yet — show a redacted placeholder in
    /// the accent colour rather than a real balance (`CHECKLIST.md`
    /// "Spring/matched-geometry transition").
    var isLoading = false

    var body: some View {
        VStack(spacing: 8) {
            if isLoading {
                Text("Your balance")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("₹0,000")
                    .font(heroFont)
                    .redacted(reason: .placeholder)
            } else if balances.isEmpty {
                Text("You're all settled up")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                Text(balances.count == 1 ? headline(for: balances[0]) : "Your balance")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                VStack(spacing: 4) {
                    ForEach(balances, id: \.currency) { balance in
                        Text(amountLine(for: balance))
                            .font(heroFont)
                            .foregroundStyle(balance.netMinor > 0 ? .green : .red)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        // A raised card, not flat on the canvas — the one clear focal point
        // on Group Home (`CHECKLIST.md` "Shadow/elevation on hero card"),
        // washed with this group's two-stop accent gradient (`CHECKLIST.md`
        // "Per-group accent color" + `DESIGN_BIBLE.md` §3) so it carries the
        // group's identity with a hint of depth.
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Surface.raised)
                .overlay { if let wash { wash } }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .shadow(color: (accent ?? .black).opacity(accent == nil ? 0.06 : 0.18), radius: 14, y: 5)
        .padding(.horizontal)
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }

    /// The balance is the number a person looks at most, so it stays on SF
    /// Rounded rather than the display face (Space Grotesk's geometric digits
    /// and cramped ₹ read a touch calculator-ish at this size — owner call);
    /// still tabular so it doesn't jiggle as balances change.
    private var heroFont: Font {
        .system(size: 28, weight: .bold, design: .rounded).monospacedDigit()
    }

    private func headline(for balance: Balance) -> String {
        balance.netMinor > 0 ? "You are owed" : "You owe"
    }

    /// For a single currency the sign is carried by the headline, so show the
    /// bare amount; for multiple, prefix each so a mixed row still reads. A
    /// thin space sits between the currency symbol and the first digit — calmer
    /// than "₹1,200" jammed together at hero size, and only here (list rows
    /// stay tight).
    private func amountLine(for balance: Balance) -> String {
        let amount = MoneyFormat.string(minorUnits: abs(balance.netMinor), currency: balance.currency)
        let spaced = spacingCurrencySymbol(amount)
        guard balances.count > 1 else { return spaced }
        return balance.netMinor > 0 ? "owed \(spaced)" : "owe \(spaced)"
    }

    /// Insert a thin space (U+2009) before the first digit when it's preceded
    /// by a currency symbol — "₹ 1,200", "$ 5". Leaves an already-spaced or
    /// suffix-symbol format untouched.
    private func spacingCurrencySymbol(_ s: String) -> String {
        guard let firstDigit = s.firstIndex(where: \.isNumber), firstDigit != s.startIndex else { return s }
        let before = s[s.index(before: firstDigit)]
        guard !before.isWhitespace, !before.isNumber else { return s }
        return s[..<firstDigit] + "\u{2009}" + s[firstDigit...]
    }
}
