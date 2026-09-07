import SwiftUI

extension View {
    /// Translucent sheet chrome (`CHECKLIST.md` "Materials/blur on sheets") —
    /// the sheet blurs whatever's behind it instead of sitting as a flat
    /// opaque panel. Applied to a sheet's root content (the `NavigationStack`).
    /// A `Form`/`List` inside still paints its own grouped background over the
    /// material, so pair this with `.materialSheetContent()` on that scroll
    /// view to let the blur show through its gutters.
    func materialSheet() -> some View {
        presentationBackground(.regularMaterial)
    }

    /// Hide a `Form`/`List`'s own scroll background so the sheet's material
    /// (`materialSheet()`) shows through the margins around its row groups.
    /// The inset-grouped section rows keep their own fill for legibility.
    func materialSheetContent() -> some View {
        scrollContentBackground(.hidden)
    }
}
