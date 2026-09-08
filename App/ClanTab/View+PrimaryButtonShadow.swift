import SwiftUI

extension View {
    /// A soft, accent-tinted lift under a primary (`.borderedProminent`)
    /// call-to-action (`CHECKLIST.md` "Shadow/elevation on … primary
    /// buttons") — enough to separate it from the surface, not a drop
    /// shadow. Only for the one prominent action on a screen, never every
    /// button. `active: false` (a disabled/grey button) drops the tinted
    /// shadow so it doesn't sit oddly under an inert control.
    func primaryButtonShadow(active: Bool = true) -> some View {
        shadow(color: .accentColor.opacity(active ? 0.25 : 0), radius: 8, y: 3)
    }
}
