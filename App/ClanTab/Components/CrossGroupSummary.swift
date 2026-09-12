import ClanTabKit

/// "You owe Bob ₹1,200 · $15" / "Bob owes you ₹300" / a mixed-direction line /
/// "Settled up" — the cross-group net balance line shared by `FriendsView`'s
/// row and `FriendDetailView`'s balance section. Used to live on the
/// now-retired standalone `PeopleView` ("Settle Across Groups";
/// `CHECKLIST.md` UX audit [8] folded its one screen's worth of capability
/// into the Friends tab).
enum CrossGroupSummary {
    static func line(_ net: [CrossGroupNet], name: String) -> String {
        let youOwe = net.filter { $0.netMinor > 0 }
        let theyOwe = net.filter { $0.netMinor < 0 }

        func list(_ items: [CrossGroupNet]) -> String {
            items.map { MoneyFormat.string(minorUnits: abs($0.netMinor), currency: $0.currency) }
                .joined(separator: " · ")
        }

        switch (youOwe.isEmpty, theyOwe.isEmpty) {
        case (false, true): return "You owe \(name) \(list(youOwe))"
        case (true, false): return "\(name) owes you \(list(theyOwe))"
        case (false, false): return "You owe \(list(youOwe)); \(name) owes you \(list(theyOwe))"
        case (true, true): return "Settled up"
        }
    }
}
