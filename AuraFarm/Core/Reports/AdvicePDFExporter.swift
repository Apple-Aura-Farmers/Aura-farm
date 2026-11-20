import CoreGraphics
import CoreTransferable
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// Writes the field report as a PDF, one A4 page for each page of `AdviceReportPages`.
///
/// The pages are SwiftUI views drawn straight into the PDF, so text stays text (it can be selected
/// and searched) and the shapes stay sharp when printed.
///
/// Writing never touches the app's state: it reads the report value it is given and writes a file
/// to the temporary folder. Nothing on the farm's page or on Home changes when it runs, finishes
/// or is cancelled.
@MainActor
enum AdvicePDFExporter {
    enum Failure: Error {
        case couldNotCreateFile
    }

    /// A4 in points.
    static let pageSize = CGSize(width: 595, height: 842)

    /// Writes the report to a temporary file and returns where it is.
    static func write(_ report: AdviceReport, to directory: URL = FileManager.default.temporaryDirectory)
        throws -> URL
    {
        let url = directory.appending(path: fileName(for: report))
        try? FileManager.default.removeItem(at: url)

        var box = CGRect(origin: .zero, size: pageSize)
        let info =
            [
                kCGPDFContextTitle as String: String(localized: "Field report for \(report.farmName)"),
                kCGPDFContextCreator as String: "Aura Farm",
            ] as CFDictionary
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, info) else {
            throw Failure.couldNotCreateFile
        }

        for page in AdviceReportPages.pages(for: withFrames(report)) {
            let renderer = ImageRenderer(content: page)
            renderer.proposedSize = ProposedViewSize(pageSize)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }

    /// The report with its microscope frames read and made small. A frame that cannot be read is
    /// left out, never replaced by a placeholder.
    static func withFrames(_ report: AdviceReport) -> AdviceReport {
        var report = report
        report.frames = report.frameSources.compactMap { source in
            thumbnailJPEG(at: source.url).map { AdviceReport.Frame(jpeg: $0, caption: source.caption) }
        }
        return report
    }

    /// A JPEG at most `maxPixels` on its long side, so the PDF stays small.
    static func thumbnailJPEG(at url: URL, maxPixels: Int = 900) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateThumbnailAtIndex(
                source, 0,
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary)
        else { return nil }
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    /// "Aura-Farm-Report-Subak-Jatiluwih-2026-11-10.pdf"
    static func fileName(for report: AdviceReport) -> String {
        let name = report.farmName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let day = report.sampledAt.formatted(.iso8601.year().month().day())
        return "Aura-Farm-Report-\(name.isEmpty ? "Farm" : name)-\(day).pdf"
    }
}

/// The report as something the share sheet can send. The PDF is only written when a place to send
/// it to has been chosen, so showing the button costs nothing.
struct ExportableAdvice: Transferable, Sendable {
    let report: AdviceReport

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            let url = try await MainActor.run { try AdvicePDFExporter.write(item.report) }
            return SentTransferredFile(url)
        }
    }
}
