import Foundation

/// Saves a finished guided scan as a sweep in the app's normal store, so the results screen and
/// Publish work on it as on any other. It keeps no frames: the counts come from the run's map,
/// and the run record (path, edges, organisms) and the movement CSV are saved in the folder.
///
/// This is its own path and does not go through `SweepRecorder.finish`, whose "No frames were
/// kept" failure belongs to the capture screen and stays as it is.
enum GuidedScanSaver {
    static let runRecordFileName = "run.json"
    static let movementFileName = "movement.csv"

    enum Failure: Error, Equatable, LocalizedError {
        case folderNotCreated
        case notSaved

        var errorDescription: String? {
            switch self {
            case .folderNotCreated: "The folder for this scan could not be created."
            case .notSaved: "The scan could not be saved."
            }
        }
    }

    /// Writes the sweep's folder and returns its name.
    /// - Parameters:
    ///   - movementCSV: the run's movement log, copied in; nil when there is none.
    ///   - directory: where sweeps live.
    @discardableResult
    static func save(
        details: SampleDetails, record: GuideRunRecord, movementCSV: URL?,
        in directory: URL = SweepRecorder.sweepsDirectory
    ) throws -> String {
        let folder = SweepRecorder.freeURL(base: details.fileBaseName, in: directory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw Failure.folderNotCreated
        }

        do {
            let json = try GuideRunRecord.encoder().encode(record)
            try json.write(to: folder.appending(path: runRecordFileName), options: .atomic)
            var bytes = json.count
            if let movementCSV {
                let target = folder.appending(path: movementFileName)
                try FileManager.default.copyItem(at: movementCSV, to: target)
                bytes += (try? target.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            }
            let manifest = SweepManifest(
                details: details, frameCount: 0, byteCount: bytes, stoppedEarly: false,
                panoramaFile: nil, panoramaProblem: nil, organismCounts: record.countsByLabel,
                guidedScan: true)
            try SweepRecorder.writeManifest(manifest, inSweepAt: folder)
        } catch {
            throw Failure.notSaved
        }
        return folder.lastPathComponent
    }

    /// The run record saved in a sweep's folder; nil for a sweep without one (the capture
    /// screen's).
    static func runRecord(in folder: URL) -> GuideRunRecord? {
        (try? Data(contentsOf: folder.appending(path: runRecordFileName)))
            .flatMap { try? GuideRunRecord.decoder().decode(GuideRunRecord.self, from: $0) }
    }
}
