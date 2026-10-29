import AVFoundation
import Observation

/// Records raw clips and writes a metadata sidecar next to each one.
/// Raw footage is the source for training data: every clip gets a free name and
/// nothing already on disk is overwritten or edited.
@Observable
final class ClipRecorder: NSObject {
    private(set) var isRecording = false
    private(set) var lastSavedName: String?
    private(set) var errorMessage: String?

    @ObservationIgnored let output = AVCaptureMovieFileOutput()
    @ObservationIgnored private var metadata: RecordingMetadata?

    /// Documents/RawClips. Visible in the Files app so clips can be copied off the phone.
    static var clipsDirectory: URL {
        URL.documentsDirectory.appending(path: "RawClips", directoryHint: .isDirectory)
    }

    func start(metadata: RecordingMetadata) {
        guard !output.isRecording else { return }
        do {
            try FileManager.default.createDirectory(
                at: Self.clipsDirectory, withIntermediateDirectories: true)
        } catch {
            errorMessage = "The clip folder could not be created."
            return
        }

        self.metadata = metadata
        errorMessage = nil
        output.startRecording(
            to: Self.freeURL(base: metadata.fileBaseName, extension: "mov"),
            recordingDelegate: self
        )
        isRecording = true
    }

    func stop() {
        guard output.isRecording else { return }
        output.stopRecording()
    }

    /// A URL no file uses yet, so an existing raw clip is never overwritten.
    static func freeURL(base: String, extension ext: String, in directory: URL = clipsDirectory) -> URL {
        var candidate = directory.appending(path: "\(base).\(ext)")
        var suffix = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appending(path: "\(base)-\(suffix).\(ext)")
            suffix += 1
        }
        return candidate
    }

    /// Sidecar JSON beside the clip, same base name.
    static func writeSidecar(_ metadata: RecordingMetadata, forClipAt clipURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let sidecarURL = clipURL.deletingPathExtension().appendingPathExtension("json")
        try encoder.encode(metadata).write(to: sidecarURL, options: .atomic)
    }
}

extension ClipRecorder: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let metadata = self.metadata
        self.metadata = nil

        // Some stops report an error and still leave a usable file.
        let finishedCleanly =
            (error as NSError?)?
            .userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)

        var failure: String?
        if !finishedCleanly {
            // The clip is kept either way: raw footage is never deleted here.
            failure = "Recording stopped early. The clip was kept, check it before using it."
        }
        if let metadata {
            do {
                try Self.writeSidecar(metadata, forClipAt: outputFileURL)
            } catch {
                failure = "The clip was saved but its sample details were not."
            }
        }

        let savedName = outputFileURL.lastPathComponent
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isRecording = false
            self.lastSavedName = savedName
            self.errorMessage = failure
        }
    }
}
