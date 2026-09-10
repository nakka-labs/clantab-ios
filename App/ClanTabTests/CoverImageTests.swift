import XCTest
import UIKit
@testable import ClanTab

/// `CoverImage` — client-side downscale + 16:9 crop before a group cover is
/// uploaded (`CHECKLIST.md` "Group cover image").
final class CoverImageTests: XCTestCase {

    private func solidImage(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testDownscalesAndCropsToSixteenNine() throws {
        // A tall 3:4 photo → cropped to 16:9, scaled to the target width.
        let data = try XCTUnwrap(CoverImage.jpegData(from: solidImage(width: 3024, height: 4032)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width, CoverImage.width, accuracy: 1)
        XCTAssertEqual(out.size.width / out.size.height, CoverImage.aspect, accuracy: 0.02)
    }

    func testAlreadyWideImageKeepsAspectAfterCrop() throws {
        // A very wide 3:1 panorama → cropped to 16:9 (trims the sides).
        let data = try XCTUnwrap(CoverImage.jpegData(from: solidImage(width: 3000, height: 1000)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width / out.size.height, CoverImage.aspect, accuracy: 0.02)
    }

    func testOutputIsWellUnderTheServerSizeCap() throws {
        let data = try XCTUnwrap(CoverImage.jpegData(from: solidImage(width: 4032, height: 3024, scale: 2)))
        XCTAssertLessThan(data.count, 800_000)
    }

    func testIsDeterministic() throws {
        let image = solidImage(width: 2000, height: 1500)
        XCTAssertEqual(
            try XCTUnwrap(CoverImage.jpegData(from: image)),
            try XCTUnwrap(CoverImage.jpegData(from: image))
        )
    }
}
