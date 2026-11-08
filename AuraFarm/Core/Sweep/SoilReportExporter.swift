import AuraFarmKit
import CryptoKit
import Foundation

/// Turns a saved sweep into the soil report the farm manager on a Mac reads.
///
/// Read only, like the rest of the library: the report is written to a temporary file for the
/// share sheet, and nothing in the sweep's folder is changed.
enum SoilReportExporter {
    enum Failure: Error, Equatable, LocalizedError {
        case noSampleDetails
        case notCounted

        var errorDescription: String? {
            switch self {
            case .noSampleDetails:
                return "This sweep has no sample details, so it cannot be sent."
            case .notCounted:
                return "Nothing was counted in this sweep, so there is no result to send."
            }
        }
    }

    /// The report for a sweep. Organism groups are listed most counted first, and groups the
    /// detector did not find are left out.
    static func report(
        for sweep: SavedSweep,
        createdAt: Date = .now,
        bundle: Bundle = .main
    ) throws -> SoilReport {
        guard let manifest = sweep.manifest else { throw Failure.noSampleDetails }
        guard let counts = manifest.organismCounts else { throw Failure.notCounted }

        let details = manifest.details
        let organisms =
            counts
            .filter { $0.value > 0 }
            .map { SoilReport.OrganismCount(taxon: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.taxon < $1.taxon }

        return SoilReport(
            id: reportID(for: sweep),
            createdAt: createdAt,
            sample: SoilReport.Sample(
                sampleID: details.sampleID,
                microscopeField: details.field,
                moisture: details.moisture.rawValue,
                gramsOfSoil: details.gramsOfSoil,
                millilitresScanned: details.millilitresScanned,
                // Every slide is made to the one recipe, so that is what this one followed.
                millilitresOfWater: SamplePreparation.millilitresOfWater,
                preparation: SamplePreparation.summary,
                recordedAt: details.recordedAt
            ),
            capture: SoilReport.Capture(
                frameCount: manifest.frameCount,
                stoppedEarly: manifest.stoppedEarly,
                detectorModel: OrganismDetector.modelName,
                appVersion: appVersion(of: bundle)
            ),
            organisms: organisms,
            panoramaJPEG: sweep.panoramaURL.flatMap { try? Data(contentsOf: $0) }
        )
    }

    /// Writes the report to a temporary file and returns where, for the share sheet.
    static func writeTemporaryFile(for sweep: SavedSweep) throws -> URL {
        let report = try report(for: sweep)
        let directory = URL.temporaryDirectory.appending(path: "SoilReports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: report.suggestedFileName)
        try SoilReportCodec.encode(report).write(to: url, options: .atomic)
        return url
    }

    /// The same for every send of one sweep, so the farm manager knows a repeat when it sees
    /// one. Taken from the sweep's folder name, which holds the sample ID and the UTC time it
    /// was recorded and is never reused on a phone.
    static func reportID(for sweep: SavedSweep) -> UUID {
        var bytes = Array(SHA256.hash(data: Data(sweep.name.utf8)).prefix(16))
        // Mark it as a name-based UUID (version 5 layout, RFC 4122 variant).
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: bytes.withUnsafeBytes { $0.load(as: uuid_t.self) })
    }

    private static func appVersion(of bundle: Bundle) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(version) (\(build))"
    }
}
