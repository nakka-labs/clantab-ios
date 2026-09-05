import WidgetKit
import SwiftUI

/// The one home-screen widget (`FEATURE_BACKLOG.md` "Home-screen widget") —
/// no user configuration for v1, always the most-recently-opened group
/// (whatever `GroupViewModel` last wrote a snapshot for).
struct ClanTabBalanceWidget: Widget {
    // Must match `AppConfig.balanceWidgetKind` exactly — `WidgetCenter`
    // addresses widgets by this string, not by type.
    let kind = AppConfig.balanceWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BalanceTimelineProvider()) { entry in
            BalanceWidgetView(entry: entry)
        }
        .configurationDisplayName("ClanTab Balance")
        .description("See what you owe or are owed in your most recent group.")
        .supportedFamilies([.systemSmall])
    }
}
