import SwiftUI
import UIKit

extension View {
    /// Adds a "Done" button above the keyboard (dismisses it) plus
    /// swipe-down-to-dismiss on the scroll view. Needed because `.decimalPad` /
    /// `.numberPad` have no return key, and SwiftUI `Form` text fields don't
    /// resign on Return either.
    func dismissibleKeyboard() -> some View {
        modifier(DismissibleKeyboard())
    }
}

private struct DismissibleKeyboard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                    }
                }
            }
    }
}
