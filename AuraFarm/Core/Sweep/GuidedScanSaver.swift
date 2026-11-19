import Foundation

/// Saves a finished guided scan as a sweep in the app's normal store, so the results screen and
/// Publish work on it as on any other. It keeps no frames: the counts come from the run's map,
/// and the run record (path, edges, organisms) and the movement CSV are saved in the folder.
///
/// This is its own path and does not write frames, so the old recorder's "No frames were
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
    ///   - lensVideo: the recorded video, hard-linked in (copied when that is not possible); if
    ///     neither works the sweep is saved without it and the record does not name it.
    ///   - directory: where sweeps live.
    @discardableResult
    static func save(
        details: SampleDetails, record: GuideRunRecord, movementCSV: URL?, lensVideo: URL? = nil,
        in directory: URL = SweepStore.sweepsDirectory
    ) throws -> String {
        var record = record
        let folder = SweepStore.freeURL(base: details.fileBaseName, in: directory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw Failure.folderNotCreated
        }

        if let name = record.lensVideoFile {
            let target = folder.appending(path: name)
            let fileManager = FileManager.default
            var kept = false
            if let lensVideo {
                kept =
                    (try? fileManager.linkItem(at: lensVideo, to: target)) != nil
                    || (try? fileManager.copyItem(at: lensVideo, to: target)) != nil
            }
            if !kept {
                record.lensVideoFile = nil
                record.lensVideoScanStartSeconds = nil
            }
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
                guidedScan: true,
                fieldsScanned: record.spotsTicked)
            try SweepStore.writeManifest(manifest, inSweepAt: folder)
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
