import SwiftUI

extension Animation {
    /// The one confirm-moment spring (`DESIGN_BIBLE.md` §5) — reused for every
    /// spring / matched-geometry transition tied to a confirming action, so the
    /// app (and, eventually, the whole portfolio) moves with a single
    /// consistent feel rather than a curve picked per call site. Settled, a
    /// touch of give, never bouncy.
    ///
    /// Named after settling up (`claim` + `settle`), ClanTab's most significant
    /// confirm. Current call sites: the delete/undo toast on Group Home. As
    /// more confirm-moment transitions land (a settle-up animation, the
    /// deferred open-a-group hero), they use this rather than `.default`.
    static let claimSettle = Animation.spring(response: 0.4, dampingFraction: 0.85)
}
