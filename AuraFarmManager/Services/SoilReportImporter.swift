import AuraFarmKit
import Foundation
import SwiftData

/// Files soil reports from the field app as soil tests, in the inbox.
///
/// A report already imported is recognised by its ID and skipped, so sending a sweep twice,
/// or opening the same file again, never doubles a result.
@MainActor
struct SoilReportImporter {
    enum Outcome: Equatable {
        case imported(SoilTest)
        case alreadyImported(SoilTest)
    }

    let context: ModelContext

    /// Reads a `.aurafarm` file. The file may come from outside the sandbox (AirDrop, a drop
    /// from Finder, the open panel), so access is asked for while it is read.
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
}
