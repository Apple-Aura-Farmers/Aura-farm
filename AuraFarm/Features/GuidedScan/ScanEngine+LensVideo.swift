import AVFoundation
import UIKit

/// The engine's side of the lens recording: when it starts and ends, and what it logs. The
/// recorder itself is `LensRecorder`; it never blocks the analysis queue. State here is on the
/// analysis queue.
extension ScanEngine {
    static let lensVideoFolder = "LensVideos"

    /// Whether to record, from the guided scan's switch or the lab's. On starts a new recording
    /// at once when the camera is running; off finishes the one in progress and keeps it.
    func setRecordsLensVideo(_ enabled: Bool) {
        analysisQueue.async { [self] in
            recordsLensVideo = enabled
            if enabled { startLensVideo() } else { finishLensVideo() }
        }
    }

    /// Starts Documents/LensVideos/lens-<stamp>.mov when recording is wanted and the camera runs.
    func startLensVideo() {
        guard recordsLensVideo, cameraRunning, lensRecorder == nil else { return }
        let url = DetectionSnapshotWriter.documents
            .appending(path: Self.lensVideoFolder)
            .appending(path: "lens-\(Self.lensStamp()).mov")
        lensRecorder = LensRecorder(url: url) { [weak self] reason in
            self?.analysisQueue.async { self?.lensEvents.append(("lens_video_failed", reason)) }
        }
        lensResult = nil
        lensScanStartOffset = nil
        lensEvents.append(("lens_video_started", url.lastPathComponent))
    }

    /// Ends the recording in progress, if any; `then` gets what the last recording came to (nil if
    /// there was none). Safe to call again.
    func finishLensVideo(then: ((LensRecorder.Result?) -> Void)? = nil) {
        guard let recorder = lensRecorder else {
            then?(lensResult)
            return
        }
        lensRecorder = nil
        lensFinishing.append(recorder)
        // The file is finished even if the engine has gone: only the bookkeeping is weak.
        recorder.finish { [weak self] result in
            guard let self else { return }
            self.analysisQueue.async {
                self.lensFinishing.removeAll { $0 === recorder }
                // Discarded while it was being closed: the recorder deleted the file itself.
                guard !recorder.isDiscarded else {
                    then?(nil)
                    return
                }
                if self.lensRecorder == nil { self.lensResult = result }
                self.lensEvents.append(
                    (
                        "lens_video_finished",
                        String(format: "duration=%.1f s frames=%d", result.duration, result.framesWritten)
                    ))
                let note = Self.lensVideoNote(for: result)
                DispatchQueue.main.async { self.lensVideoNote = note }
                then?(result)
            }
        }
    }

    /// Throws the recording away: the one in progress is ended and its file deleted, with any
    /// still being closed, and what an earlier one came to is forgotten, so nothing can attach it
    /// to a later run (a manual look saves nothing). Safe to call twice.
    func discardLensVideo() {
        analysisQueue.async { [self] in
            lensFinishing.forEach { $0.discard() }
            let kept = lensResult?.url
            lensResult = nil
            lensScanStartOffset = nil
            if let kept { try? FileManager.default.removeItem(at: kept) }
            guard let recorder = lensRecorder else { return }
            lensRecorder = nil
            recorder.discard()
            lensEvents.append(("lens_video_discarded", recorder.url.lastPathComponent))
        }
    }

    /// The offset of "Start scan" in the video, once, as an event.
    func noteLensScanStart() {
        guard let origin = lensRecorder?.originSeconds else { return }
        let offset = max(lastCapturedSeconds - origin, 0)
        lensScanStartOffset = offset
        lensEvents.append(("lens_video_scan_start", String(format: "%.2f", offset)))
    }

    /// The video that belongs in the sweep: the one that holds the scan's start and exists.
    func lensVideoForRun(_ result: LensRecorder.Result?) -> URL? {
        guard lensScanStartOffset != nil, let url = result?.url ?? lensResult?.url,
            FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    /// The running count of frames left out of the video (the CSV's `video_drops`).
    var lensVideoDrops: Int { lensRecorder?.videoDrops ?? lensResult?.videoDrops ?? 0 }

    /// "Video saved (2.3 GB available)", or why it stopped; empty when nothing was recorded.
    static func lensVideoNote(for result: LensRecorder.Result?, available: Int64? = nil) -> String {
        guard let result, result.framesWritten > 0 || result.failure != nil else { return "" }
        if result.outOfSpace { return "Video stopped: the phone is out of space" }
        if let failure = result.failure { return "Video stopped: \(failure)" }
        let free =
            available
            ?? (try? DetectionSnapshotWriter.documents
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                .volumeAvailableCapacityForImportantUsage) ?? 0
        let text = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
        return "Video saved (\(text) available)"
    }

    private static func lensStamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    // MARK: Ways a recording ends besides the route and `stop()`

    func observeLensVideoEnders() {
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(lensVideoMustEnd),
            name: AVCaptureSession.wasInterruptedNotification, object: session)
        center.addObserver(
            self, selector: #selector(lensVideoMustEnd),
            name: AVCaptureSession.runtimeErrorNotification, object: session)
        center.addObserver(
            self, selector: #selector(appEnteredBackground),
            name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// The camera was interrupted or failed: the partly recorded file is finished, not lost.
    @objc private func lensVideoMustEnd() {
        analysisQueue.async { [self] in finishLensVideo() }
    }

    /// Background: the same, with a little time borrowed so the file can be closed.
    @objc private func appEnteredBackground() {
        let task = UIApplication.shared.beginBackgroundTask()
        analysisQueue.async { [self] in
            endFocusTest()
            finishLensVideo { _ in
                DispatchQueue.main.async { UIApplication.shared.endBackgroundTask(task) }
            }
        }
    }
}
