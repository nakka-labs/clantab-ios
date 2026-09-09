import ClanTabKit
import CoreGraphics
import SwiftUI
import UIKit

/// Rasterises `GroupReportView` to a one-page PDF on disk (`FEATURE_BACKLOG.md`
/// "PDF export"), for a `ShareLink(item: url)`. `ImageRenderer` draws the
/// SwiftUI page straight into a PDF `CGContext` — no PDFKit needed to *make* a
/// PDF (that's for viewing/editing).
enum GroupReportPDF {
    /// Writes the report for `state` to a temp `.pdf` and returns its URL, or
    /// `nil` if rendering failed. `@MainActor` — `ImageRenderer` is main-actor.
    @MainActor
    static func write(from state: GroupStateResponse) -> URL? {
        let model = GroupReportModel.build(from: state)
        let filename = "\(ExportFile.sanitizedFilename(state.group.name))-report.pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        let renderer = ImageRenderer(content: GroupReportView(model: model))
        var wrote = false
        renderer.render { size, renderInContext in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            renderInContext(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            wrote = true
        }
        return wrote && FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
