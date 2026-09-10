import UIKit

/// Client-side downscale + compress before a receipt photo is uploaded
/// (`CHECKLIST.md` "Photo attachment on an expense"). Unlike `ProfileImage` /
/// `CoverImage` there's no crop — a receipt has to stay readable, so the whole
/// frame is kept and only scaled down to fit `maxEdge` on its longest side.
enum ReceiptImage {
    /// ~2000px longest edge, q0.8 → a phone photo of a receipt lands a few
    /// hundred KB, well under the 5 MB server cap, and text stays legible when
    /// zoomed.
    static let maxEdge: CGFloat = 2000
    static let quality: CGFloat = 0.8

    /// `nil` if the image can't be encoded.
    static func jpegData(from image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())

        if scale == 1 {
            return image.jpegData(compressionQuality: quality)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
