import Foundation

/// Where sweeps live on the phone and how a folder for one is made: the parts of saving a sweep
/// the guided scan, the sweep library and the old frame-writing recorder share.
enum SweepStore {
    /// Documents/FrameSets. Visible in the Files app so sweeps can be copied off the phone.
    static var sweepsDirectory: URL {
        URL.documentsDirectory.appending(path: "FrameSets", directoryHint: .isDirectory)
    }

    static let panoramaFileName = "panorama.jpg"

    /// A directory URL nothing uses yet, so an existing sweep is never written into.
    static func freeURL(base: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: base, directoryHint: .isDirectory)
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)-\(suffix)", directoryHint: .isDirectory)
            suffix += 1
        }
        return candidate
    }

    /// `manifest.json` inside the sweep's folder.
    static func writeManifest(_ manifest: SweepManifest, inSweepAt folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: folder.appending(path: "manifest.json"), options: .atomic)
    }
}
