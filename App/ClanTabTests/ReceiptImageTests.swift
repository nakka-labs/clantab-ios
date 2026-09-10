import XCTest
import UIKit
@testable import ClanTab

/// `ReceiptImage` — downscale + compress before a receipt photo is uploaded
/// (`CHECKLIST.md` "Photo attachment on an expense"). No crop: the whole frame
/// is kept, only scaled to fit `maxEdge`.
final class ReceiptImageTests: XCTestCase {

    private func solidImage(width: CGFloat, height: CGFloat, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    func testScalesTheLongEdgeToTheCapAndKeepsAspect() throws {
        // A tall 3:4 photo well over the cap.
        let data = try XCTUnwrap(ReceiptImage.jpegData(from: solidImage(width: 3024, height: 4032)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(max(out.size.width, out.size.height), ReceiptImage.maxEdge, accuracy: 1)
        XCTAssertEqual(out.size.width / out.size.height, 3.0 / 4.0, accuracy: 0.02) // aspect preserved, no crop
    }

    func testAnAlreadySmallImageIsLeftAtItsSize() throws {
        let data = try XCTUnwrap(ReceiptImage.jpegData(from: solidImage(width: 800, height: 600)))
        let out = try XCTUnwrap(UIImage(data: data))
        XCTAssertEqual(out.size.width, 800, accuracy: 1)
        XCTAssertEqual(out.size.height, 600, accuracy: 1)
    }

    func testOutputIsWellUnderTheServerSizeCap() throws {
        let data = try XCTUnwrap(ReceiptImage.jpegData(from: solidImage(width: 4032, height: 3024, scale: 2)))
        XCTAssertLessThan(data.count, 2_000_000) // 5 MB server cap
    }
}
