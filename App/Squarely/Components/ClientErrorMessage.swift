import Foundation
import SquareKit

/// Turns a thrown error — typically a `SquarelyClientError` — into copy a user
/// can actually read, for the plain error `Text` shown under each form.
func friendlyMessage(for error: Error) -> String {
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
        }
    }
    if let clientError = error as? SquarelyClientError {
        switch clientError {
        case .server(_, let message):
            return message
        case .notFound:
            return "That group or code couldn't be found."
        case .invalidResponse, .decodingFailed:
            return "Something went wrong talking to Squarely. Please try again."
        }
    }
    return error.localizedDescription
}
