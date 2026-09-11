import ClanTabKit

/// App-side display copy for `SplitType` — the kit stays UI-free, so this
/// lives here rather than on the model itself. Shared by `AddExpenseView`'s
/// segmented control / summary row and `MoreSplitsSheet` (`CHECKLIST.md` UX
/// audit [15]).
extension SplitType {
    var shortLabel: String {
        switch self {
        case .equal: return "Equally"
        case .exact: return "Exact"
        case .percentage: return "%"
        case .shares: return "Shares"
        case .itemized: return "Items"
        }
    }

    var fullLabel: String {
        switch self {
        case .equal: return "Equally"
        case .exact: return "Exact Amounts"
        case .percentage: return "Percentages"
        case .shares: return "Shares"
        case .itemized: return "Items"
        }
    }

    var detail: String {
        switch self {
        case .equal: return "Split evenly among everyone included"
        case .exact: return "Enter each person's exact amount"
        case .percentage: return "Split by a percentage each"
        case .shares: return "Split by ratio — A gets twice as much as B"
        case .itemized: return "Line by line — split each item only among who shared it"
        }
    }
}
