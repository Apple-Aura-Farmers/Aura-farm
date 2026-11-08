import AVFoundation
import CoreImage
import CoreText
import CoreVideo
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

/// Runs the detector over a recorded video and keeps a picture of every organism it finds.
///
/// This is the model's workbench: no sweep rules, no quality check, no stitching. Every
/// third frame goes through the detector, the tally gives each thing found an id and follows
/// it so it is not counted twice, and a frame is saved the moment something appears that was
/// not there before. One picture per organism, with its box and id drawn on, is what makes
/// the model easy to judge.
///
/// Pictures land in Documents/Detections, which is visible in the Files app. Nothing here
/// touches the video it reads.
@Observable
final class VideoDetectionRunner {
    private(set) var isRunning = false
    /// What happened, once a run is over.
    private(set) var outcome: String?
    private(set) var savedFrames: [URL] = []
    private(set) var countByLabel: [String: Int] = [:]
    private(set) var total = 0

    @ObservationIgnored private let queue = DispatchQueue(label: "video.detection")

    /// Every third frame, matching the roughly 10 fps the camera screen analyzes at.
    static let analyzeEveryNthFrame = 3
    /// Give up after this much footage, so a long recording cannot run for ever.
    static let maxSecondsRead = 180.0
    /// A ceiling on pictures kept from one run, so a noisy model cannot fill the store.
    static let maxSavedFrames = 120

    /// Where the pictures land.
    static var detectionsDirectory: URL {
        URL.documentsDirectory.appending(path: "Detections", directoryHint: .isDirectory)
    }

    func run(videoURL: URL, startSeconds: Double) {
        guard !isRunning else { return }
        isRunning = true
        outcome = nil
        savedFrames = []
        countByLabel = [:]
        total = 0

        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.detect(videoURL: videoURL, startSeconds: startSeconds)
            DispatchQueue.main.async {
                self.isRunning = false
                self.outcome = result.message
                self.savedFrames = result.frames
                self.countByLabel = result.countByLabel
                self.total = result.total
            }
        }
    }

    private struct Result {
        var message: String
        var frames: [URL] = []
        var countByLabel: [String: Int] = [:]
        var total = 0
    }

    private static func detect(videoURL: URL, startSeconds: Double) -> Result {
        let detector: OrganismDetector
        do {
            detector = try OrganismDetector(computeUnits: .cpuAndGPU)
        } catch {
            return Result(message: error.localizedDescription)
        }

        let asset = AVURLAsset(url: videoURL)
        guard let track = try? awaitFirstVideoTrack(of: asset),
            let reader = try? AVAssetReader(asset: asset)
        else {
            return Result(message: "The video could not be opened.")
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                // The same pixel format the camera hands over, so the model sees what it
                // would see live.
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        guard reader.canAdd(output) else { return Result(message: "The video could not be read.") }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(startSeconds, 0), preferredTimescale: 600),
            duration: CMTime(seconds: maxSecondsRead, preferredTimescale: 600)
        )
        guard reader.startReading() else { return Result(message: "The video could not be read.") }

        let folder = detectionsDirectory.appending(
            path: folderName(for: videoURL), directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            return Result(message: "The folder for the pictures could not be created.")
        }

        let context = CIContext(options: [.useSoftwareRenderer: false])
        let shake = ShakeEstimator()
        var tally = OrganismTally()
        var frameNumber = 0
        var analyzed = 0
        var milliseconds: [Double] = []
        var saved: [URL] = []

        while let sample = output.copyNextSampleBuffer() {
            frameNumber += 1
            guard frameNumber % analyzeEveryNthFrame == 0,
                let buffer = CMSampleBufferGetImageBuffer(sample)
            else { continue }

            analyzed += 1
            _ = shake.update(with: buffer)

            let started = CFAbsoluteTimeGetCurrent()
            let detections = (try? detector.detections(in: buffer)) ?? []
            milliseconds.append((CFAbsoluteTimeGetCurrent() - started) * 1000)

            let width = Double(CVPixelBufferGetWidth(buffer))
            let height = Double(CVPixelBufferGetHeight(buffer))
            let appeared = tally.update(
                found: detections.map { detection in
                    OrganismTally.Found(
                        label: detection.label,
                        // Vision counts from the bottom left; everything else here counts
                        // from the top left.
                        box: CGRect(
                            x: detection.box.minX * width,
                            y: (1 - detection.box.maxY) * height,
                            width: detection.box.width * width,
                            height: detection.box.height * height
                        ),
                        confidence: detection.confidence
                    )
                },
                pictureMoved: CaptureViewModel.pictureMoved(registered: shake.lastShift)
            )

            // A picture is kept when something new turns up, not on every frame that has
            // anything in it: the same organism is in shot for many frames running.
            guard !appeared.isEmpty, saved.count < maxSavedFrames else { continue }
            let name = String(format: "frame-%04d.jpg", analyzed)
            if let url = write(
                buffer: buffer, tracks: tally.visible, to: folder.appending(path: name),
                context: context)
            {
                saved.append(url)
            }
        }
        reader.cancelReading()

        var message = "Read \(analyzed) frames."
        if analyzed == 0 {
            message += " Nothing could be read from this part of the video."
        } else {
            let median = milliseconds.sorted()[milliseconds.count / 2]
            message += String(
                format: " %d found, %d pictures kept. %.1f ms a frame.",
                tally.total, saved.count, median)
        }
        if saved.count >= maxSavedFrames {
            message += " The picture limit was reached, so the run stopped keeping them."
        }
        return Result(
            message: message, frames: saved, countByLabel: tally.countByLabel, total: tally.total)
    }

    /// Writes one frame with every box and id drawn on it, so the picture alone says what the
    /// model saw.
    private static func write(
        buffer: CVPixelBuffer, tracks: [OrganismTally.Track], to url: URL, context: CIContext
    ) -> URL? {
        let image = CIImage(cvPixelBuffer: buffer)
        guard let base = context.createCGImage(image, from: image.extent) else { return nil }

        let width = base.width
        let height = base.height
        guard
            let canvas = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        canvas.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        // The canvas counts from the bottom left and the boxes from the top left, so flip
        // them as they are drawn.
        let green = CGColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1)
        canvas.setStrokeColor(green)
        canvas.setLineWidth(max(Double(width) / 300, 2))
        // Big enough to read when the picture is shrunk to fit a phone screen.
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, Double(width) / 40, nil)
        for track in tracks {
            let box = CGRect(
                x: track.box.minX,
                y: Double(height) - track.box.maxY,
                width: track.box.width,
                height: track.box.height
            )
            canvas.stroke(box)
            // The same caption as the live preview: which organism this is, and what of.
            let caption = CTLineCreateWithAttributedString(
                NSAttributedString(
                    string: "\(track.id) \(track.label)",
                    attributes: [
                        NSAttributedString.Key(kCTFontAttributeName as String): font,
                        NSAttributedString.Key(kCTForegroundColorAttributeName as String): green,
                    ]))
            canvas.textPosition = CGPoint(x: box.minX, y: box.maxY + Double(width) / 200)
            CTLineDraw(caption, canvas)
        }
        guard let drawn = canvas.makeImage() else { return nil }

        guard
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(
            destination, drawn, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return url
    }

    /// One folder per run, named after the video and when it ran.
    private static func folderName(for videoURL: URL) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withColonSeparatorInTime]
        let when = stamp.string(from: .now).replacingOccurrences(of: ":", with: "-")
        return "\(videoURL.deletingPathExtension().lastPathComponent)-\(when)"
    }

    /// AVFoundation's track loading is async; this run is already off the main thread.
    private static func awaitFirstVideoTrack(of asset: AVAsset) throws -> AVAssetTrack? {
        let semaphore = DispatchSemaphore(value: 0)
        var found: AVAssetTrack?
        var failure: Error?
        Task {
            do { found = try await asset.loadTracks(withMediaType: .video).first } catch {
                failure = error
            }
            semaphore.signal()
        }
        semaphore.wait()
        if let failure { throw failure }
        return found
    }
}
