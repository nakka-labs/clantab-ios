import XCTest
import UIKit
@testable import ClanTab

/// `ProfileImage` — client-side downscale + compress before a profile photo is
/// uploaded (`CHECKLIST.md` "Profile photos").
final class ProfileImageTests: XCTestCase {

    private func solidImage(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testDownscalesALargeImageToTheTargetEdgeAndSquares() throws {
        let data = try XCTUnwrap(ProfileImage.jpegData(from: solidImage(width: 3000, height: 2000)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width, ProfileImage.edge, accuracy: 1)
        XCTAssertEqual(out.size.height, ProfileImage.edge, accuracy: 1)
    }

    func testAlreadySquareAndSmallStillComesBackAsJPEGAtTheTargetEdge() throws {
        let data = try XCTUnwrap(ProfileImage.jpegData(from: solidImage(width: 200, height: 200)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width, ProfileImage.edge, accuracy: 1)
        XCTAssertEqual(out.size.height, ProfileImage.edge, accuracy: 1)
    }

    func testOutputIsWellUnderTheServerSizeCap() throws {
        // 5 MB server cap (worker/src/lib/media.ts). A 512px q0.7 JPEG of a
        // photographic image is tens of KB; a flat colour is far less. Just
        // assert we're comfortably inside.
        let data = try XCTUnwrap(ProfileImage.jpegData(from: solidImage(width: 4032, height: 3024, scale: 2)))
        XCTAssertLessThan(data.count, 500_000)
    }

    func testIsDeterministicForTheSameInput() throws {
        let image = solidImage(width: 1000, height: 800)
        let a = try XCTUnwrap(ProfileImage.jpegData(from: image))
        let b = try XCTUnwrap(ProfileImage.jpegData(from: image))
        XCTAssertEqual(a, b)
    }
}
