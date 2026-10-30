import AVFoundation
import CoreVideo
import Foundation
import Observation

/// Runs a recorded video through the capture pipeline, frame by frame, as if it were coming
/// from the camera: the same analyzer, the same quality check, the same sweep rules and the
/// same writer. It exists so stitching can be tried against real microscope footage on a
/// machine with no microscope attached.
///
/// It writes an ordinary sweep, so what comes out can be opened in Saved sweeps like any
/// other. Nothing here touches the video it reads.
@Observable
final class VideoSweepRunner {
    private(set) var isRunning = false
    private(set) var progress = FrameSweep().progress
    /// What happened, once a run is over.
    private(set) var outcome: String?
    private(set) var savedName: String?

    @ObservationIgnored private let queue = DispatchQueue(label: "video.sweep")

    /// Analyze every Nth frame of the video, matching the camera's roughly 10 fps.
    static let analyzeEveryNthFrame = 3
    /// Give up after this much footage, so a 40 minute recording cannot run for ever.
    static let maxSecondsRead = 180.0

    /// - Parameter startSeconds: where to begin. Most of a recording is not a steady pan
    ///   across a slide, so the part worth testing has to be picked by hand.
    func run(videoURL: URL, startSeconds: Double, details: RecordingMetadata) {
        guard !isRunning else { return }
        isRunning = true
        outcome = nil
        savedName = nil

        queue.async { [weak self] in
            guard let self else { return }
            let result = Self.sweep(videoURL: videoURL, startSeconds: startSeconds, details: details)
            DispatchQueue.main.async {
                self.isRunning = false
                self.outcome = result.message
                self.savedName = result.savedName
                self.progress = result.progress
            }
        }
    }

    private static func sweep(
        videoURL: URL, startSeconds: Double, details: RecordingMetadata
    ) -> (message: String, savedName: String?, progress: SweepProgress) {
        let sweep = FrameSweep()
        let monitor = CaptureQualityMonitor()
        let shake = ShakeEstimator()
        let recorder = FrameSetRecorder()

        let asset = AVURLAsset(url: videoURL)
        guard let track = try? awaitFirstVideoTrack(of: asset),
            let reader = try? AVAssetReader(asset: asset)
        else {
            return ("The video could not be opened.", nil, sweep.progress)
        }

        let output = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: [
                // The same pixel format the camera hands over, so the analyzer behaves the same.
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
        )
        guard reader.canAdd(output) else {
            return ("The video could not be read.", nil, sweep.progress)
        }
        reader.add(output)
        reader.timeRange = CMTimeRange(
            start: CMTime(seconds: max(startSeconds, 0), preferredTimescale: 600),
            duration: CMTime(seconds: maxSecondsRead, preferredTimescale: 600)
        )
        guard reader.startReading() else {
            return ("The video could not be read.", nil, sweep.progress)
        }

        guard recorder.begin(details: details) else {
            return ("The folder for this sweep could not be created.", nil, sweep.progress)
        }

        var frameNumber = 0
        var analyzed = 0
        while !sweep.isFinished, let sample = output.copyNextSampleBuffer() {
            frameNumber += 1
            guard frameNumber % analyzeEveryNthFrame == 0,
                let buffer = CMSampleBufferGetImageBuffer(sample),
                let stats = FrameAnalyzer.brightnessAndSharpness(of: buffer)
            else { continue }

            analyzed += 1
            let reading = CaptureQualityReading(
                brightness: stats.brightness,
                sharpness: stats.sharpness,
                shakePixels: shake.update(with: buffer)
            )
            monitor.update(with: reading)

            let step = sweep.update(
                isSettled: monitor.hasSettled,
                issue: monitor.topIssue,
                shift: shake.lastShift
            )
            if step == .keepFrame, let bytes = recorder.write(buffer) {
                sweep.addWrittenBytes(bytes)
            }
        }
        reader.cancelReading()

        let kept = sweep.keptCount
        let savedName = recorder.finish(stoppedEarly: !sweep.isFinished)

        var message = "Read \(analyzed) frames, kept \(kept)."
        if kept == 0 {
            message +=
                " Nothing was steady and sharp enough, or the view never travelled far enough"
                + " between frames."
        } else if kept < sweep.thresholds.framesPerSweep {
            message += " The footage ran out before the sweep was full."
        }
        return (message, savedName, sweep.progress)
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
