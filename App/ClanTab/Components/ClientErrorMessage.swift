import Foundation
import ClanTabKit

/// Turns a thrown error — typically a `ClanTabClientError` — into copy a user
/// can actually read, for the plain error `Text` shown under each form.
func friendlyMessage(for error: Error) -> String {
    // Checked first, before `ClanTabClientError` — a transport-level failure
    // (no connection, a timeout) never reaches `ClanTabClient` at all; it
    // surfaces as a raw `URLError` straight from `URLSession`, which would
    // otherwise fall through to `error.localizedDescription` at the bottom
    // (`CHECKLIST.md` UX audit [33]). Distinguishing it from a genuine server/
    // decoding failure matters: one says "check your connection," the other
    // says "try again" — different diagnoses, same generic message before.
    if isOffline(error) {
        return "No internet connection. Check your connection and try again."
    }
    if let validationError = error as? ValidationError {
        switch validationError {
        case .emptySplits:
            return "Add at least one person to split with."
        case .splitMismatch:
            return "The splits don't add up to the total amount."
        case .unknownMember:
            return "One of the selected people isn't in this group."
        case .invalidAmount:
            return "Enter an amount greater than zero."
        case .emptyItems:
            return "Add at least one item."
        case .itemWithoutParticipants:
            return "Every item needs at least one person sharing it."
        case .itemSumMismatch:
            return "The items don't add up to the total amount."
        case .emptyShares:
            return "Give at least one person a share."
        case .invalidShareWeight:
            return "Shares must be whole numbers, and at least one person needs a share."
        case .emptyPayers:
            return "Add at least one payer."
        case .payerSumMismatch:
            return "The payers don't add up to the total amount."
        }
    }
    if let clientError = error as? ClanTabClientError {
        switch clientError {
        case .server(_, let message):
            return message
        case .notFound:
            return "That group or code couldn't be found."
        case .invalidResponse, .decodingFailed:
            return "Something went wrong talking to ClanTab. Please try again."
        }
    }
    return error.localizedDescription
}

/// Walks `NSUnderlyingErrorKey` a few levels down — `URLSession` and the
/// frameworks built on it often wrap a plain `URLError` inside their own
/// error domain. Mirrors `SignInErrorMessage.isOffline`, kept as a separate
/// copy since the two files are independently testable and scoped to
/// different callers (sign-in vs. every other network call).
private func isOffline(_ error: Error) -> Bool {
    var current: Error? = error
    var depth = 0
    while let err = current, depth < 5 {
        let nsError = err as NSError
        if nsError.domain == NSURLErrorDomain { return true }
        current = nsError.userInfo[NSUnderlyingErrorKey] as? Error
        depth += 1
    }
    return false
}
