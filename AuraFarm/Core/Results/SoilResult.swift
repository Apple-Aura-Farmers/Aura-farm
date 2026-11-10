import Foundation

/// Everything the results screen shows, gathered in one value so the screen never reads a
/// sweep's files itself.
///
/// This is the one place to change when the data behind a result changes: the screen, the
/// estimate and the recommendation all read from here. Test scenarios build one directly,
/// without a sweep on disk.
struct SoilResult: Equatable {
    var sampleID: String
    var recordedAt: Date
    /// Frames kept in the sweep. The estimate reads abundance per frame, so a short sweep is
    /// not mistaken for poor soil.
    var framesKept: Int
    var moisture: SampleDetails.Moisture
    /// What the detector counted, by its class label. Empty when it ran and found nothing;
    /// nil when it did not run, so a sweep that was never counted is not read as empty.
    var countsByClass: [String: Int]?
    /// The saved sweep this came from, for sending it on and looking through its frames.
    /// nil for a result made up for testing.
    var sweep: SavedSweep?

    enum Failure: Error, Equatable, LocalizedError {
        case noSampleDetails

        var errorDescription: String? {
            switch self {
            case .noSampleDetails:
                return "This sweep has no sample details, so there is no result to show."
            }
        }
    }

    /// Every organism counted, or nil when the sweep was not counted.
    var totalCount: Int? {
        countsByClass.map { $0.values.reduce(0, +) }
    }

    /// The classes found at least once.
    var classesFound: Int {
        countsByClass?.values.filter { $0 > 0 }.count ?? 0
    }
}

extension SoilResult {
    /// The result for a saved sweep. Throws when the sweep has no manifest, because without
    /// it nothing says what the sample was.
    init(sweep: SavedSweep) throws {
        guard let manifest = sweep.manifest else { throw Failure.noSampleDetails }
        self.init(
            sampleID: manifest.details.sampleID,
            recordedAt: manifest.details.recordedAt,
            framesKept: manifest.frameCount,
            moisture: manifest.details.moisture,
            countsByClass: manifest.organismCounts,
            sweep: sweep
        )
    }
}
