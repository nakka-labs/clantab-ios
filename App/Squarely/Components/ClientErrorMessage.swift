import Foundation
import SquareKit

/// Turns a thrown error — typically a `SquarelyClientError` — into copy a user
/// can actually read, for the plain error `Text` shown under each form.
func friendlyMessage(for error: Error) -> String {
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
