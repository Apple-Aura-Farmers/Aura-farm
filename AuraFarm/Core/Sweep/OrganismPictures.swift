import AuraFarmKit
import Foundation

/// One organism picture of a saved sweep, ready to send.
struct OrganismPicture: Equatable {
    /// What the report says about it: the label, and its path in the records' storage.
    var image: SoilReport.OrganismImage
    /// The JPEG on the phone.
    var file: URL
}

/// Finds the organism pictures that belong to a saved sweep.
enum OrganismPictures {
    /// Where the lab and the guided scan keep their runs.
    static var runsDirectory: URL {
        URL.documentsDirectory.appending(path: "SlideLab/Runs", directoryHint: .isDirectory)
    }

    /// The pictures the sweep's run record names and the phone still has, in the order they were
    /// counted. Empty for a sweep without them.
    static func of(_ sweep: SavedSweep, runs: URL = runsDirectory) -> [OrganismPicture] {
        guard let record = GuidedScanSaver.runRecord(in: sweep.url),
            let folder = folder(for: record, in: sweep, runs: runs)
        else { return [] }
        let id = SoilReportExporter.reportID(for: sweep).uuidString.lowercased()
        return record.organisms.compactMap { organism in
            guard let name = organism.image else { return nil }
            let file = folder.appending(path: name)
            guard FileManager.default.fileExists(atPath: file.path) else { return nil }
            return OrganismPicture(
                image: SoilReport.OrganismImage(taxon: organism.label, path: "\(id)/\(name)"),
                file: file)
        }
    }

    /// The sweep's own folder of pictures. A sweep saved before it had one: the folder of the run
    /// it was made from, found by the run's times.
    private static func folder(for record: GuideRunRecord, in sweep: SavedSweep, runs: URL) -> URL? {
        let own = sweep.url.appending(path: GuidedScanSaver.organismsFolderName)
        if FileManager.default.fileExists(atPath: own.path) { return own }
        guard record.organisms.contains(where: { $0.image != nil }) else { return nil }
        let files =
            (try? FileManager.default.contentsOfDirectory(at: runs, includingPropertiesForKeys: nil)) ?? []
        let run = files.first { file in
            guard file.pathExtension == "json",
                let other = (try? Data(contentsOf: file))
                    .flatMap({ try? GuideRunRecord.decoder().decode(GuideRunRecord.self, from: $0) })
            else { return false }
            return other.started == record.started && other.ended == record.ended
        }
        return run.map { $0.deletingPathExtension().path + "-organisms" }
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
    }
}
