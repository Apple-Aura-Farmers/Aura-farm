import Foundation

/// A raw clip on disk, with the sample details that were written beside it.
struct SavedClip: Identifiable, Equatable {
    var url: URL
    /// nil when the sidecar is missing or unreadable. The clip is still listed.
    var metadata: RecordingMetadata?
    var recordedAt: Date
    var byteCount: Int64

    var id: URL { url }
    var name: String { url.lastPathComponent }
}

/// Lists what is in the raw clips folder. Read only: nothing here moves, edits or deletes a clip.
enum ClipLibrary {
    static func clips(in directory: URL = ClipRecorder.clipsDirectory) -> [SavedClip] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys
        )) ?? []

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return urls
            .filter { $0.pathExtension.lowercased() == "mov" }
            .map { url in
                let sidecar = url.deletingPathExtension().appendingPathExtension("json")
                let metadata = (try? Data(contentsOf: sidecar))
                    .flatMap { try? decoder.decode(RecordingMetadata.self, from: $0) }
                let values = try? url.resourceValues(forKeys: Set(keys))
                return SavedClip(
                    url: url,
                    metadata: metadata,
                    recordedAt: metadata?.recordedAt ?? values?.contentModificationDate ?? .distantPast,
                    byteCount: Int64(values?.fileSize ?? 0)
                )
            }
            .sorted { $0.recordedAt > $1.recordedAt }
    }
}
