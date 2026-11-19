import AVFoundation

/// Records the camera's own frames (the raw pixel buffers, 1280x720, unrotated) to a .mov, as a
/// passive copy of what the scan is given. It never blocks the caller: `offer` only takes a lock
/// and queues work for the recorder's own serial queue, and a frame the writer cannot take is
/// dropped from the video alone (`videoDrops`).
final class LensRecorder: @unchecked Sendable {
    /// What a recording came to.
    struct Result: Equatable {
        var url: URL
        /// Last frame's time minus the first's.
        var duration: Double
        var framesWritten: Int
        var videoDrops: Int
        /// Why the recording stopped early (`outOfSpace` says it was the disk); nil when it did not.
        var failure: String?
        var outOfSpace: Bool
    }

    /// The video size: the camera's own, so the file can be replayed through the lab's video path.
    static let width = 1280
    static let height = 720
    /// PLACEHOLDER: about 60 MB a minute.
    static let bitsPerSecond = 8_000_000
    /// Frames waiting for the writer's queue. The camera has only a few buffers, so holding more
    /// would starve it and change the scan; a frame beyond this is a video drop.
    static let maxPending = 3

    let url: URL
    private let queue: DispatchQueue
    private let lock = NSLock()
    // Guarded by `lock`.
    private var pending = 0
    private var drops = 0
    private var origin: Double?
    private var finished = false
    private var failure: (reason: String, outOfSpace: Bool)?
    private var result: Result?
    // Writer queue only.
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var sessionStarted = false
    private var firstSeconds = 0.0
    private var lastSeconds = 0.0
    private var written = 0
    private var onFailure: ((String) -> Void)?

    /// - Parameters:
    ///   - queue: the recorder's own serial queue (a test can hold it to keep the writer busy).
    ///   - onFailure: called once, on the recorder's queue, with the reason the writer failed; the
    ///     scan carries on untouched.
    init(
        url: URL, queue: DispatchQueue = DispatchQueue(label: "lens.recorder"),
        onFailure: ((String) -> Void)? = nil
    ) {
        self.url = url
        self.queue = queue
        self.onFailure = onFailure
    }

    /// The first frame's time, once one was offered.
    var originSeconds: Double? { lock.withLock { origin } }
    var videoDrops: Int { lock.withLock { drops } }
    /// Frames handed over and not yet taken by the writer.
    var pendingFrames: Int { lock.withLock { pending } }
    /// True once the writer failed or the recording was finished.
    var isStopped: Bool { lock.withLock { finished || failure != nil } }

    /// Hands a frame to the writer's queue and returns at once.
    func offer(_ sampleBuffer: CMSampleBuffer) {
        let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let accepted: Bool = lock.withLock {
            guard !finished, failure == nil else { return false }
            if pending >= Self.maxPending {
                drops += 1
                return false
            }
            if origin == nil { origin = seconds }
            pending += 1
            return true
        }
        guard accepted else { return }
        queue.async { [self] in
            append(sampleBuffer)
            lock.withLock { pending -= 1 }
        }
    }

    /// Ends the recording and calls `completion` (on the recorder's queue) with the result; the file
    /// is playable if any frame was written, otherwise it is removed. A second call gets the same
    /// result.
    func finish(_ completion: @escaping (Result) -> Void) {
        lock.withLock { finished = true }
        queue.async { [self] in
            if let result {
                completion(result)
                return
            }
            guard let writer, let input, sessionStarted, writer.status == .writing else {
                writer?.cancelWriting()
                try? FileManager.default.removeItem(at: url)
                complete(completion)
                return
            }
            input.markAsFinished()
            writer.finishWriting { [self] in
                queue.async {
                    if writer.status == .failed { recordFailure(writer.error) }
                    complete(completion)
                }
            }
        }
    }

    // MARK: Writer queue

    private func append(_ sampleBuffer: CMSampleBuffer) {
        // Frames handed over before `finish` still count; only a failure stops the writing.
        guard lock.withLock({ failure == nil }) else { return }
        if writer == nil, !startWriter(at: sampleBuffer) { return }
        guard let writer, let input else { return }
        if writer.status == .failed {
            recordFailure(writer.error)
            return
        }
        guard input.isReadyForMoreMediaData else {
            lock.withLock { drops += 1 }
            return
        }
        if input.append(sampleBuffer) {
            let seconds = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            lastSeconds = seconds
            written += 1
        } else {
            recordFailure(writer.error)
        }
    }

    /// The writer, with its session starting at this first frame's time so the video plays at the
    /// session's real speed.
    private func startWriter(at sampleBuffer: CMSampleBuffer) -> Bool {
        do {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let input = AVAssetWriterInput(
                mediaType: .video,
                outputSettings: [
                    AVVideoCodecKey: AVVideoCodecType.hevc,
                    AVVideoWidthKey: Self.width, AVVideoHeightKey: Self.height,
                    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Self.bitsPerSecond],
                ])
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                recordFailure(nil, fallback: "The video input could not be added.")
                return false
            }
            writer.add(input)
            guard writer.startWriting() else {
                recordFailure(writer.error)
                return false
            }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            writer.startSession(atSourceTime: time)
            firstSeconds = time.seconds
            lastSeconds = firstSeconds
            self.writer = writer
            self.input = input
            sessionStarted = true
            return true
        } catch {
            recordFailure(error)
            return false
        }
    }

    /// Stops recording and keeps the reason, once.
    private func recordFailure(_ error: Error?, fallback: String = "The video could not be written.") {
        let nsError = error as NSError?
        let space =
            nsError?.domain == NSCocoaErrorDomain && nsError?.code == NSFileWriteOutOfSpaceError
            || nsError?.code == AVError.diskFull.rawValue
            || (nsError?.userInfo[NSUnderlyingErrorKey] as? NSError)?.code == Int(ENOSPC)
        let reason = error?.localizedDescription ?? fallback
        let isFirst = lock.withLock { () -> Bool in
            guard failure == nil else { return false }
            failure = (reason, space)
            return true
        }
        guard isFirst else { return }
        print("LENS VIDEO failed: \(reason)")
        onFailure?(reason)
        onFailure = nil
        // A partly written file is still finished when `finish` runs.
    }

    private func complete(_ completion: (Result) -> Void) {
        let failed = lock.withLock { failure }
        let result = Result(
            url: url, duration: lastSeconds - firstSeconds, framesWritten: written,
            videoDrops: videoDrops, failure: failed?.reason, outOfSpace: failed?.outOfSpace ?? false)
        self.result = result
        completion(result)
    }
}
