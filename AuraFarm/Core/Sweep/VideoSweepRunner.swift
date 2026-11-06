import AVFoundation
import CoreVideo
import Foundation
import Observation

/// Runs a recorded video through the capture pipeline, frame by frame, as if it were coming
/// from the camera: the same analyzer, the same quality check, the same sweep rules and the
/// same writer, and the same detector and tally. It exists so the whole pipeline, stitching
/// and counting included, can be tried against real microscope footage without a microscope.
///
/// It writes an ordinary sweep, counts included, so what comes out can be opened in Saved
/// sweeps and sent to the Mac like any other. Nothing here touches the video it reads.
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
    func run(videoURL: URL, startSeconds: Double, details: SampleDetails) {
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
        videoURL: URL, startSeconds: Double, details: SampleDetails
    ) -> (message: String, savedName: String?, progress: SweepProgress) {
        let sweep = FrameSweep()
        let monitor = CaptureQualityMonitor()
        let shake = ShakeEstimator()
        let recorder = SweepRecorder()
        // This is the stitching workbench, so joining the frames is the point of the run.
        recorder.joinsFrames = true

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

        // Counting the way the camera does. A sweep is still worth having if the detector
        // cannot open, so its counts are saved as missing rather than as zero.
        let detector = try? OrganismDetector(computeUnits: .cpuAndGPU)
        var tally = OrganismTally()

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

            // Every analyzed frame is counted, kept or not, as on the camera: the tally needs
            // to see the ground between kept frames to follow what it has already counted.
            if let detector, let detections = try? detector.detections(in: buffer) {
                let width = Double(CVPixelBufferGetWidth(buffer))
                let height = Double(CVPixelBufferGetHeight(buffer))
                tally.update(
                    found: detections.map { OrganismTally.Found($0, frameWidth: width, frameHeight: height) },
                    pictureMoved: CaptureViewModel.pictureMoved(registered: shake.lastShift)
                )
            }

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
        let finished = recorder.finish(
            stoppedEarly: !sweep.isFinished,
            organismCounts: detector == nil ? nil : tally.countByLabel
        )

        var message = "Read \(analyzed) frames, kept \(kept)."
        message += detector == nil ? " The detector could not open." : " Counted \(tally.total)."
        if kept == 0 {
            message +=
                " Nothing was steady and sharp enough, or the view never travelled far enough"
                + " between frames."
        } else if kept < sweep.thresholds.framesPerSweep {
            message += " The footage ran out before the sweep was full."
        }
        // Whether the frames joined is the point of running this, so it is said outright.
        if kept > 0 {
            message += " " + (finished?.panoramaProblem ?? "They joined into one picture.")
        }
        return (message, finished?.name, sweep.progress)
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
