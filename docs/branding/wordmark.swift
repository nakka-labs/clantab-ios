import Foundation
import AppKit
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ClanTab wordmark: the "=" mark + "ClanTab" in SF Pro Rounded Bold, glyphs
// flattened to vector paths so the SVG renders identically without the font.
// Outputs SVG (dark + white) and PNG (dark + white) into the given directory.

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// --- geometry, in a 1000-unit design space (height) --------------------------
let H: CGFloat = 1000                 // overall art height
let capH: CGFloat = 640               // cap height of the text / mark height
let fontSize: CGFloat = 895           // tuned so cap height ≈ capH for SF Rounded Bold
let markW = capH * 1.02               // mark bar length
let barH = capH * 0.235
let barGap = capH * 0.185
let gapAfterMark = capH * 0.42        // space between mark and first letter

// --- build the "ClanTab" glyph path -----------------------------------------
let baseFont = NSFont.systemFont(ofSize: fontSize, weight: .bold)
let roundedDesc = baseFont.fontDescriptor.withDesign(.rounded) ?? baseFont.fontDescriptor
let ctFont = CTFontCreateWithFontDescriptor(roundedDesc as CTFontDescriptor, fontSize, nil)

let text = "ClanTab"
var glyphs = [CGGlyph](repeating: 0, count: text.count)
let uni = Array(text.unicodeScalars).map { UniChar($0.value) }
CTFontGetGlyphsForCharacters(ctFont, uni, &glyphs, text.count)

let word = CGMutablePath()
var pen: CGFloat = 0
var advances = [CGSize](repeating: .zero, count: glyphs.count)
CTFontGetAdvancesForGlyphs(ctFont, .horizontal, glyphs, &advances, glyphs.count)
for (i, g) in glyphs.enumerated() {
    if let gp = CTFontCreatePathForGlyph(ctFont, g, nil) {
        let t = CGAffineTransform(translationX: pen, y: 0)
        word.addPath(gp, transform: t)
    }
    pen += advances[i].width
}
let wordBox = word.boundingBoxOfPath   // origin at baseline; y up

// --- compose: mark on the left, word to its right, baseline-aligned ---------
// The mark sits vertically centred on the text's cap band.
let textLeft = markW + gapAfterMark
// Shift the word so its visual left edge starts at textLeft, baseline at 0.
let wordShiftX = textLeft - wordBox.minX
let totalW = textLeft + wordBox.width + capH * 0.06   // tiny right padding
let baseline = (H - capH) / 2 + (-wordBox.minY)       // put cap band centred

func markPath() -> CGPath {
    let p = CGMutablePath()
    let top = baseline - (-wordBox.minY) + (capH - (barH * 2 + barGap)) / 2  // align mark band to cap band
    let r = barH / 2
    p.addRoundedRect(in: CGRect(x: 0, y: top + barH + barGap, width: markW, height: barH), cornerWidth: r, cornerHeight: r)
    p.addRoundedRect(in: CGRect(x: 0, y: top, width: markW, height: barH), cornerWidth: r, cornerHeight: r)
    return p
}

// --- SVG emission ----------------------------------------------------------
// Convert a CGPath (y-up) into an SVG path string flipped to y-down (viewBox H).
func svgPathData(_ path: CGPath, dx: CGFloat = 0) -> String {
    var out = ""
    path.applyWithBlock { elPtr in
        let el = elPtr.pointee
        let p = el.points
        func X(_ i: Int) -> String { String(format: "%.2f", p[i].x + dx) }
        func Y(_ i: Int) -> String { String(format: "%.2f", H - p[i].y) }
        switch el.type {
        case .moveToPoint:    out += "M\(X(0)) \(Y(0)) "
        case .addLineToPoint: out += "L\(X(0)) \(Y(0)) "
        case .addQuadCurveToPoint: out += "Q\(X(0)) \(Y(0)) \(X(1)) \(Y(1)) "
        case .addCurveToPoint: out += "C\(X(0)) \(Y(0)) \(X(1)) \(Y(1)) \(X(2)) \(Y(2)) "
        case .closeSubpath:   out += "Z "
        @unknown default: break
        }
    }
    return out.trimmingCharacters(in: .whitespaces)
}

let markD = svgPathData(markPath())
let wordD = svgPathData(word, dx: wordShiftX)
// baseline flip: our paths are in y-up with baseline at `baseline`; shift up by `baseline`
func lift(_ d: String) -> String { d } // handled per-point via Y(): H - (y). Add baseline via translate.

func svg(markColor: String, textColor: String) -> String {
    """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(totalW)) \(Int(H))" width="\(Int(totalW))" height="\(Int(H))" role="img" aria-label="ClanTab">
      <g transform="translate(0,\(String(format: "%.2f", -baseline)))">
        <path d="\(markD)" fill="\(markColor)"/>
        <path d="\(wordD)" fill="\(textColor)"/>
      </g>
    </svg>
    """
}

let blue = "#0074CA"
let ink = "#15161A"
try svg(markColor: blue, textColor: ink).write(to: outDir.appendingPathComponent("wordmark.svg"), atomically: true, encoding: .utf8)
try svg(markColor: "#FFFFFF", textColor: "#FFFFFF").write(to: outDir.appendingPathComponent("wordmark-white.svg"), atomically: true, encoding: .utf8)

// --- PNG rasterisation ---------------------------------------------------
func rasterise(markCG: CGColor, textCG: CGColor, widthPx: Int, to url: URL) {
    let scale = CGFloat(widthPx) / totalW
    let hPx = Int((H * scale).rounded())
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: widthPx, height: hPx, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: baseline)   // move to baseline coords (y-up)
    ctx.addPath(markPath()); ctx.setFillColor(markCG); ctx.fillPath()
    let shifted = CGMutablePath()
    shifted.addPath(word, transform: CGAffineTransform(translationX: wordShiftX, y: 0))
    ctx.addPath(shifted); ctx.setFillColor(textCG); ctx.fillPath()
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
}

rasterise(markCG: CGColor(red: 0, green: 116/255, blue: 202/255, alpha: 1),
          textCG: CGColor(red: 21/255, green: 22/255, blue: 26/255, alpha: 1),
          widthPx: 2400, to: outDir.appendingPathComponent("wordmark@2x.png"))
rasterise(markCG: CGColor(red: 0, green: 116/255, blue: 202/255, alpha: 1),
          textCG: CGColor(red: 21/255, green: 22/255, blue: 26/255, alpha: 1),
          widthPx: 1200, to: outDir.appendingPathComponent("wordmark.png"))
rasterise(markCG: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
          textCG: CGColor(red: 1, green: 1, blue: 1, alpha: 1),
          widthPx: 1200, to: outDir.appendingPathComponent("wordmark-white.png"))

print("wordmark: \(Int(totalW))×\(Int(H)) design units → \(outDir.path)")
