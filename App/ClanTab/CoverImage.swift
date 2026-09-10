import UIKit

/// Client-side downscale + compress before a group cover image is uploaded
/// (`CHECKLIST.md` "Group cover image") — the sibling of `ProfileImage` for a
/// wide banner instead of a square avatar. Crops to 16:9 around the centre,
/// scales the width to `width`, JPEG-encodes at `quality`. The display views
/// crop further with `.scaledToFill()`; this just caps what gets uploaded.
enum CoverImage {
    /// ~1280×720, q0.75 → a photographic cover lands a few hundred KB, well
    /// under the 5 MB server cap.
    static let width: CGFloat = 1280
    static let aspect: CGFloat = 16.0 / 9.0
    static let quality: CGFloat = 0.75

    /// `nil` if the image can't be encoded.
    static func jpegData(from image: UIImage) -> Data? {
        let cropped = centreCropped(image, aspect: aspect)
        let scale = width / max(cropped.size.width, 1)
        let target = CGSize(width: width, height: (cropped.size.height * scale).rounded())

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            cropped.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Centre-crop `image` to `aspect` (width ÷ height). Whichever dimension is
    /// proportionally too big gets trimmed.
    private static func centreCropped(_ image: UIImage, aspect: CGFloat) -> UIImage {
        let (w, h) = (image.size.width, image.size.height)
        guard w > 0, h > 0 else { return image }

        var cropW = w
        var cropH = h
        if w / h > aspect {
            cropW = h * aspect
        } else {
            cropH = w / aspect
        }
        guard cropW < w - 0.5 || cropH < h - 0.5 else { return image }

        let origin = CGPoint(x: (w - cropW) / 2, y: (h - cropH) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: cropW, height: cropH), format: format).image { _ in
            image.draw(at: CGPoint(x: -origin.x, y: -origin.y))
        }
    }
}
