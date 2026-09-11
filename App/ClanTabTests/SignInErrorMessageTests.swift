import AuthenticationServices
import XCTest
@testable import ClanTab

final class SignInErrorMessageTests: XCTestCase {

    // MARK: - Apple

    func testAppleCanceledIsSilent() {
        XCTAssertNil(SignInErrorMessage.forApple(ASAuthorizationError(.canceled)))
    }

    func testAppleUnknownMeansNoAppleID() {
        XCTAssertEqual(SignInErrorMessage.forApple(ASAuthorizationError(.unknown)), SignInErrorMessage.noAppleID)
    }

    func testAppleOtherCodeIsGeneric() {
        XCTAssertEqual(SignInErrorMessage.forApple(ASAuthorizationError(.failed)), SignInErrorMessage.genericFailure)
    }

    func testAppleOfflineWinsOverUnknownCode() {
        let underlying = URLError(.notConnectedToInternet)
        let wrapped = NSError(
            domain: ASAuthorizationError.errorDomain,
            code: ASAuthorizationError.Code.unknown.rawValue,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        XCTAssertEqual(SignInErrorMessage.forApple(wrapped), SignInErrorMessage.noNetwork)
    }

    func testAppleDirectOfflineError() {
        XCTAssertEqual(SignInErrorMessage.forApple(URLError(.notConnectedToInternet)), SignInErrorMessage.noNetwork)
    }

    // MARK: - Google

    func testGoogleCanceledIsSilent() {
        XCTAssertNil(SignInErrorMessage.forGoogle(ASWebAuthenticationSessionError(.canceledLogin)))
    }

    func testGoogleOfflineError() {
        XCTAssertEqual(SignInErrorMessage.forGoogle(URLError(.timedOut)), SignInErrorMessage.noNetwork)
    }

    func testGoogleWrappedOfflineError() {
        let underlying = URLError(.networkConnectionLost)
        let wrapped = NSError(domain: "com.example.token-exchange", code: 1, userInfo: [NSUnderlyingErrorKey: underlying])
        XCTAssertEqual(SignInErrorMessage.forGoogle(wrapped), SignInErrorMessage.noNetwork)
    }

    func testGoogleOtherErrorIsGeneric() {
        let error = NSError(domain: "com.example.token-exchange", code: 1)
        XCTAssertEqual(SignInErrorMessage.forGoogle(error), SignInErrorMessage.genericFailure)
    }
}
