import Foundation

/// Flags a CSV-imported row that looks like it's already in the group's
/// ledger — the real fix for `CHECKLIST.md` "De-dupe guard on CSV import"
/// (an interim warning-only banner shipped 2026-09-09; this is the actual
/// detection it promised). Every imported row gets a fresh client-generated
/// id by design (`ImportCSVView`, so a partial import is safe to retry), so
/// nothing server-side stops the *same* file — or the same trip exported
/// from two apps by two different group members — from silently posting
/// every row twice.
///
/// This can't be an exact match: every source app rounds shares
/// differently, keeps or strips time-of-day differently, and a blank
/// description becomes ClanTab's own placeholder on the way in
/// (`CSVImport.fallbackDescription`). So it's a best-effort "same date, same
/// amount, same payer, same description" heuristic — the caller decides
/// what to do with a flag (`ImportCSVView` excludes a flagged row from the
/// import by default, but lets the user bring it back).
public enum CSVDuplicateCheck {
    /// Wide enough to absorb a source app's own timezone-naive export
    /// landing on the "wrong" side of midnight UTC relative to how ClanTab
    /// (or a different source app) recorded the same day.
    public static let defaultDayTolerance: TimeInterval = 36 * 3600
    /// A source app's own remainder-distribution when it splits a cost
    /// evenly can land a paisa/cent or two off what ClanTab itself would
    /// compute for the same split (`CSVImport.parseSettleUp`'s own comment
    /// on this) — small enough to never mask a genuinely different amount.
    public static let defaultAmountTolerance: Int64 = 2

    /// Same currency, amount within tolerance, the same resolved payer, a
    /// matching description (case/whitespace-insensitive), and within
    /// `dayTolerance` of the same moment.
    public static func isLikelyDuplicateExpense(
        date: Date, description: String, amountMinor: Int64, currency: String, payerId: String,
        against existing: [Expense],
        amountTolerance: Int64 = defaultAmountTolerance,
        dayTolerance: TimeInterval = defaultDayTolerance
    ) -> Bool {
        let normalizedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return existing.contains { candidate in
            candidate.deletedAt == nil
                && candidate.currency == currency
                && abs(candidate.amountMinor - amountMinor) <= amountTolerance
                && candidate.payers.contains { $0.memberId == payerId }
                && candidate.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(normalizedDescription) == .orderedSame
                && abs(candidate.date.timeIntervalSince(date)) <= dayTolerance
        }
    }

    /// Convenience over a parsed `CSVImport.DraftExpense`, once the caller
    /// has resolved its `payerName` to a real member id.
    public static func isLikelyDuplicate(
        _ draft: CSVImport.DraftExpense, payerId: String, against existing: [Expense],
        amountTolerance: Int64 = defaultAmountTolerance,
        dayTolerance: TimeInterval = defaultDayTolerance
    ) -> Bool {
        isLikelyDuplicateExpense(
            date: draft.date, description: draft.description, amountMinor: draft.amountMinor,
            currency: draft.currency, payerId: payerId, against: existing,
            amountTolerance: amountTolerance, dayTolerance: dayTolerance
        )
    }

    /// Same idea for a settlement: same currency, amount tolerance, same
    /// from/to pair, within `dayTolerance`. A settlement has no description
    /// to match on, so the other three signals carry the whole check — still
    /// only a flag, not a block.
    public static func isLikelyDuplicateSettlement(
        date: Date, fromId: String, toId: String, amountMinor: Int64, currency: String,
        against existing: [Settlement],
        amountTolerance: Int64 = defaultAmountTolerance,
        dayTolerance: TimeInterval = defaultDayTolerance
    ) -> Bool {
        existing.contains { candidate in
            candidate.deletedAt == nil
                && candidate.currency == currency
                && abs(candidate.amountMinor - amountMinor) <= amountTolerance
                && candidate.fromId == fromId
                && candidate.toId == toId
                && abs(candidate.date.timeIntervalSince(date)) <= dayTolerance
        }
    }

    /// Convenience over a parsed `CSVImport.DraftSettlement`, once the
    /// caller has resolved `fromName`/`toName` to real member ids.
    public static func isLikelyDuplicate(
        _ draft: CSVImport.DraftSettlement, fromId: String, toId: String, against existing: [Settlement],
        amountTolerance: Int64 = defaultAmountTolerance,
        dayTolerance: TimeInterval = defaultDayTolerance
    ) -> Bool {
        isLikelyDuplicateSettlement(
            date: draft.date, fromId: fromId, toId: toId, amountMinor: draft.amountMinor,
            currency: draft.currency, against: existing,
            amountTolerance: amountTolerance, dayTolerance: dayTolerance
        )
    }
}
