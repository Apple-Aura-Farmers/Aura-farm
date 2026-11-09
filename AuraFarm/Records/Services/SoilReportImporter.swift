import AuraFarmKit
import Foundation
import SwiftData

/// Turns finished sweeps, and soil report files from another phone, into soil tests in the
/// farm records, in the inbox until someone files them under a field.
///
/// A sweep or report already in the records is recognised by its ID and skipped, so saving a
/// sweep twice, or importing the same file again, never doubles a result.
@MainActor
struct SoilReportImporter {
    enum Outcome: Equatable {
        case imported(SoilTest)
        case alreadyImported(SoilTest)
    }

    let context: ModelContext

    /// Reads a `.aurafarm` file. The file comes from outside the app (Files, AirDrop), so
    /// access is asked for while it is read.
    func importReport(at url: URL) throws -> Outcome {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped { url.stopAccessingSecurityScopedResource() }
        }
        let data = try Data(contentsOf: url)
        return try importReport(SoilReportCodec.decode(data))
    }

    func importReport(_ report: SoilReport) throws -> Outcome {
        let reportID = report.id
        var existing = FetchDescriptor<SoilTest>(predicate: #Predicate<SoilTest> { $0.reportID == reportID })
        existing.fetchLimit = 1
        if let test = try context.fetch(existing).first {
            return .alreadyImported(test)
        }

        let test = SoilTest(report: report)
        context.insert(test)
        let counts = report.organisms.map { OrganismCount(taxon: $0.taxon, count: $0.count) }
        for count in counts {
            context.insert(count)
        }
        test.organismCounts = counts
        try context.save()
        return .imported(test)
    }

    /// Saves a sweep taken on this phone. The sweep keeps its frames on disk; the records get
    /// the counts, the sample details and the joined picture, like a report would carry.
    func importSweep(_ sweep: SavedSweep) throws -> Outcome {
        try importReport(SoilReportExporter.report(for: sweep))
    }

    /// Imports report files, counting what happened to each for the alert that follows.
    func importFiles(at urls: [URL]) -> ImportSummary {
        var summary = ImportSummary()
        for url in urls {
            record({ try importReport(at: url) }, named: url.lastPathComponent, in: &summary)
        }
        return summary
    }

    /// Saves every counted sweep on this phone that is not in the records yet. Sweeps that
    /// were not counted are left alone without counting as failures: they have nothing to save.
    func importSweeps(_ sweeps: [SavedSweep]) -> ImportSummary {
        var summary = ImportSummary()
        for sweep in sweeps where sweep.manifest?.organismCounts != nil {
            let name = sweep.manifest?.details.sampleID ?? sweep.name
            record({ try importSweep(sweep) }, named: name, in: &summary)
        }
        return summary
    }

    private func record(
        _ attempt: () throws -> Outcome,
        named name: String,
        in summary: inout ImportSummary
    ) {
        do {
            switch try attempt() {
            case .imported:
                summary.imported += 1
            case .alreadyImported:
                summary.duplicates += 1
            }
        } catch {
            summary.failures.append(ImportSummary.Failure(fileName: name, reason: error.localizedDescription))
        }
    }
}
