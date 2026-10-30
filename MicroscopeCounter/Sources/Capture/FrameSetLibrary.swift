import Foundation

/// A saved sweep on disk: a folder of frames, with the sample details written beside them.
struct SavedFrameSet: Identifiable, Equatable {
    /// The sweep's folder.
    var url: URL
    /// nil when the manifest is missing or unreadable. The sweep is still listed.
    var manifest: FrameSetManifest?
    var recordedAt: Date
    /// Total size of the frames, in bytes.
    var byteCount: Int64
    /// The frames, in the order they were taken.
    var frameURLs: [URL]

    var id: URL { url }
    var name: String { url.lastPathComponent }
    var frameCount: Int { frameURLs.count }
}

/// Lists what is in the frame sets folder. Read only: nothing here moves, edits or deletes
/// a frame. Frames are the raw data the counting work will be trained on.
enum FrameSetLibrary {
    static func frameSets(in directory: URL = FrameSetRecorder.frameSetsDirectory) -> [SavedFrameSet] {
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
            )) ?? []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return
            folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { folder in
                let manifest = (try? Data(contentsOf: folder.appending(path: "manifest.json")))
                    .flatMap { try? decoder.decode(FrameSetManifest.self, from: $0) }

                let contents =
                    (try? FileManager.default.contentsOfDirectory(
                        at: folder,
                        includingPropertiesForKeys: [.fileSizeKey]
                    )) ?? []
                let frames =
                    contents
                    .filter { $0.pathExtension.lowercased() == "jpg" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                let bytes = frames.reduce(into: Int64(0)) { total, url in
                    total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
                }

                let modified = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                return SavedFrameSet(
                    url: folder,
                    manifest: manifest,
                    recordedAt: manifest?.details.recordedAt ?? modified ?? .distantPast,
                    byteCount: bytes,
                    frameURLs: frames
                )
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }

    /// What the store holds in total. Frames replace video to stay inside it.
    /// Counted in millions, not multiples of 1024, so the screen reads "50 MB" like the
    /// limit it stands for rather than "52.4 MB".
    static let storeByteLimit: Int64 = 50 * 1_000 * 1_000

    /// Bytes used by every saved sweep. The store holds 50 MB, so the app shows how close
    /// it is to full.
    static func totalBytes(in directory: URL = FrameSetRecorder.frameSetsDirectory) -> Int64 {
        frameSets(in: directory).reduce(into: Int64(0)) { $0 += $1.byteCount }
    }
}
