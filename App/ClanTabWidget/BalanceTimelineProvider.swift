import WidgetKit
import ClanTabKit

/// One rendering of the widget: whatever `GroupViewModel` last wrote to the
/// shared snapshot, or `nil` before the app has ever written one (a fresh
/// install, or signed out — `BalanceWidgetView`'s empty state).
struct BalanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// No polling, no network calls of its own — the "lightweight refresh path"
/// `FEATURE_BACKLOG.md` calls for. The app pushes a fresh snapshot (and
/// nudges `WidgetCenter` to redraw immediately) every time it refetches the
/// group the widget is showing; `.never` here just means "nothing to redo
/// later, this entry is already used" rather than the widget picking a
/// resync time of its own.
struct BalanceTimelineProvider: TimelineProvider {
    private let store: WidgetSnapshotStoring

    init(store: WidgetSnapshotStoring = UserDefaultsWidgetSnapshotStore(defaults: AppConfig.sharedDefaults)) {
        self.store = store
    }

    func placeholder(in context: Context) -> BalanceEntry {
        BalanceEntry(date: Date(), snapshot: Self.samplePlaceholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (BalanceEntry) -> Void) {
        let snapshot = context.isPreview ? Self.samplePlaceholder : store.snapshot()
        completion(BalanceEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BalanceEntry>) -> Void) {
        completion(Timeline(entries: [BalanceEntry(date: Date(), snapshot: store.snapshot())], policy: .never))
    }

    /// Gallery preview / redacted-placeholder content — never real user data.
    static let samplePlaceholder = WidgetSnapshot(
        groupId: "preview",
        groupName: "Flatmates",
        balances: [Balance(memberId: "me", currency: "INR", netMinor: -50000)],
        updatedAt: Date()
    )
}
