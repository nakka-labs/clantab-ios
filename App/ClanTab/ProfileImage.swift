import UIKit

/// Client-side downscale + compress before a profile photo is uploaded
/// (`CHECKLIST.md` "Profile photos" step 1) — the real cost/UX lever, done even
/// though the server also caps size. Square-crops to the centre, scales the
/// short side to `edge`, and JPEG-encodes at `quality`.
enum ProfileImage {
    /// ~512 px, q0.7 → a typical avatar lands well under 100 KB (the server cap
    /// is 5 MB).
    static let edge: CGFloat = 512
    static let quality: CGFloat = 0.7

    /// `nil` if the image can't be encoded (e.g. a zero-size image).
    static func jpegData(from image: UIImage) -> Data? {
        let square = centreCropped(image)
        let scale = edge / max(square.size.width, square.size.height, 1)
        let target = CGSize(width: square.size.width * scale, height: square.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            square.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    private static func centreCropped(_ image: UIImage) -> UIImage {
        let side = min(image.size.width, image.size.height)
        guard side > 0, image.size.width != image.size.height else { return image }
        let origin = CGPoint(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }
}
