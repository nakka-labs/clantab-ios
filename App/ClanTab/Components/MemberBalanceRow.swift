import SwiftUI
import ClanTabKit

/// One row in Group Home's member list: a name and their current net balance.
struct MemberBalanceRow: View {
    let member: Member
    let netMinor: Int64
    let currency: String

    var body: some View {
        HStack {
            Text(member.displayName)
            Spacer()
            if netMinor == 0 {
                Text("settled").foregroundStyle(.secondary)
            } else {
                Text(MoneyFormat.string(minorUnits: abs(netMinor), currency: currency))
                    .foregroundStyle(netMinor > 0 ? .green : .red)
            }
        }
        // The green/red colour is the only thing distinguishing "is owed" from
        // "owes" visually — spell it out for VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let amount = MoneyFormat.string(minorUnits: abs(netMinor), currency: currency)
        if netMinor == 0 { return "\(member.displayName), settled up" }
        if netMinor > 0 { return "\(member.displayName) is owed \(amount)" }
        return "\(member.displayName) owes \(amount)"
    }
}
