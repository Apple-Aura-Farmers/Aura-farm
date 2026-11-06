import Foundation
import Observation
import SwiftData

/// Imports soil report files from wherever they arrive (the open panel, a drop on the window,
/// Finder or AirDrop) and keeps what the last import came to, for the window to show.
@MainActor
@Observable
final class SoilReportImportCoordinator {
    /// What the last import came to. The window shows it once and then clears it.
    var latestSummary: ImportSummary?
    /// Goes up by one on every import, so the window can react to each one.
    private(set) var importCount = 0

    private let importer: SoilReportImporter

    init(context: ModelContext) {
        importer = SoilReportImporter(context: context)
    }

    func importFiles(at urls: [URL]) {
        guard !urls.isEmpty else { return }
        var summary = ImportSummary()
        for url in urls {
            do {
                switch try importer.importReport(at: url) {
                case .imported:
                    summary.imported += 1
                case .alreadyImported:
                    summary.duplicates += 1
                }
            } catch {
                summary.failures.append(
                    ImportSummary.Failure(fileName: url.lastPathComponent, reason: error.localizedDescription)
                )
            }
        }
        latestSummary = summary
        importCount += 1
    }

    /// The open panel itself failed, before any file was read.
    func reportFailure(_ error: Error) {
        latestSummary = ImportSummary(
            failures: [ImportSummary.Failure(fileName: "Import", reason: error.localizedDescription)]
        )
        importCount += 1
    }
}
