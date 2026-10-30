import CoreImage
import CoreVideo
import Foundation
import ImageIO
import Observation

/// Writes a sweep as a folder of JPEG frames with a manifest beside it.
///
/// Frames replace video because the store holds 50 MB in total. A sweep of stills covers
/// several fields of view for a few MB, where a clip of the same sweep would not fit.
///
/// Frames are the raw data now, so the same rule applies as to footage: a folder already on
/// disk is never reused or overwritten, and nothing here edits or deletes a frame.
///
/// `begin`, `write` and `finish` are called from the frame analysis queue. Only the
/// published state is touched on the main queue.
@Observable
final class FrameSetRecorder {
    private(set) var isSweeping = false
    /// The frames are being joined into one image. The sweep itself is already over.
    private(set) var isJoiningFrames = false
    private(set) var keptCount = 0
    private(set) var lastSavedName: String?
    private(set) var errorMessage: String?

    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var details: RecordingMetadata?
    @ObservationIgnored private var written = 0
    @ObservationIgnored private var bytes = 0
    @ObservationIgnored private let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Documents/FrameSets. Visible in the Files app so sweeps can be copied off the phone.
    static var frameSetsDirectory: URL {
        URL.documentsDirectory.appending(path: "FrameSets", directoryHint: .isDirectory)
    }

    /// Makes the folder for a sweep. Returns false when it could not be created, in which
    /// case no frame is written.
    @discardableResult
    func begin(details: RecordingMetadata) -> Bool {
        let directory = Self.freeURL(base: details.fileBaseName, in: Self.frameSetsDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            publish { $0.errorMessage = "The folder for this sweep could not be created." }
            return false
        }

        folder = directory
        self.details = details
        written = 0
        bytes = 0
        publish {
            $0.isSweeping = true
            $0.keptCount = 0
            $0.errorMessage = nil
        }
        return true
    }

    /// Writes one frame as a JPEG. Returns the bytes written, or nil if it could not be saved.
    @discardableResult
    func write(_ pixelBuffer: CVPixelBuffer) -> Int? {
        guard let folder else { return nil }

        // The app is portrait only; the camera hands over landscape buffers, so the frame is
        // turned the way the helper saw it, as the movie connection used to do.
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        guard
            let data = context.jpegRepresentation(
                of: image,
                colorSpace: CGColorSpaceCreateDeviceRGB(),
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85]
            )
        else {
            publish { $0.errorMessage = "A frame could not be encoded." }
            return nil
        }

        let index = written + 1
        let url = folder.appending(path: String(format: "frame_%02d.jpg", index))
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            publish { $0.errorMessage = "A frame could not be saved." }
            return nil
        }

        written = index
        bytes += data.count
        let kept = written
        publish { $0.keptCount = kept }
        return data.count
    }

    /// Writes the manifest, joins the frames into one image, and ends the sweep. A sweep with
    /// no frames leaves its empty folder rather than deleting anything.
    /// Returns the sweep's folder name. The published `lastSavedName` only reaches the main
    /// queue later, so a caller that needs it at once takes it from here.
    @discardableResult
    func finish(stoppedEarly: Bool) -> String? {
        guard let folder, let details else { return nil }
        self.folder = nil
        self.details = nil
        let frameCount = written
        let frameBytes = bytes

        var failure: String?
        if frameCount == 0 {
            failure = "No frames were kept. Check the image and try again."
        } else if stoppedEarly {
            failure = "The sweep stopped at its size limit. The frames kept so far were saved."
        }
        publish {
            $0.isSweeping = false
            $0.isJoiningFrames = frameCount > 1
        }

        let joined = Self.joinFrames(in: folder)
        var manifest = FrameSetManifest(
            details: details,
            frameCount: frameCount,
            byteCount: frameBytes,
            stoppedEarly: stoppedEarly,
            panoramaFile: joined.file,
            panoramaProblem: joined.problem
        )
        if frameCount == 1 { manifest.panoramaProblem = nil }

        do {
            try Self.writeManifest(manifest, inFrameSetAt: folder)
        } catch {
            failure = "The frames were saved but their sample details were not."
        }

        let name = folder.lastPathComponent
        publish {
            $0.isJoiningFrames = false
            $0.isSweeping = false
            $0.lastSavedName = name
            $0.errorMessage = failure
        }
        return name
    }

    /// Joins a sweep's frames into one image beside them. The frames are the raw data, so a
    /// failure here leaves them exactly as they are and is only reported.
    static func joinFrames(in folder: URL) -> (file: String?, problem: String?) {
        let frames = FrameSetLibrary.frameURLs(in: folder)
        guard frames.count > 1 else { return (nil, "A panorama needs more than one frame.") }
        do {
            let panorama = try PanoramaStitcher.stitch(frameURLs: frames)
            let url = folder.appending(path: panoramaFileName)
            try PanoramaStitcher.write(panorama, to: url)
            return (panoramaFileName, nil)
        } catch {
            return (nil, "The frames could not be joined into one image. They were all kept.")
        }
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
    static func writeManifest(_ manifest: FrameSetManifest, inFrameSetAt folder: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(
            to: folder.appending(path: "manifest.json"), options: .atomic)
    }

    private func publish(_ change: @escaping (FrameSetRecorder) -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            change(self)
        }
    }
}
