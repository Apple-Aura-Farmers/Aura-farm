import Foundation

/// How a sweep across one sample is paced: how many frames to keep, how far the view has to
/// travel between them, and how much disk one sweep may use.
///
/// PLACEHOLDERS: none of these are calibrated on a real microscope setup. Set them from
/// pilot footage before relying on them.
struct SweepThresholds {
    /// Frames kept per sweep. Twelve 720p JPEGs come to roughly 4 MB.
    var framesPerSweep: Int = 12
    /// Shift (pixels) that has to build up since the last frame before another is kept, so
    /// two frames are not taken of the same field of view.
    var shiftBetweenFrames: Double = 120
    /// A single reading below this is treated as the mount wobbling rather than the slide
    /// moving, and does not count towards the shift above.
    var ignoreShiftBelow: Double = 3
    /// Hard ceiling for one sweep, so a single test cannot fill the store.
    var maxBytes: Int = 6 * 1024 * 1024
}

/// What the helper should know right now. The view turns this into one short line.
enum SweepPrompt: Equatable {
    /// Something is wrong with the image, so nothing is being kept until it is fixed.
    case fixTheImage
    /// Keep moving the slide; frames are saving by themselves.
    case moveLeft(kept: Int, of: Int)
    /// The sweep is over.
    case done(kept: Int, stoppedEarly: Bool)
}

extension SweepPrompt {
    /// Plain-language copy for a field helper: what to do, not what was measured.
    var title: String {
        switch self {
        case .fixTheImage: return "Paused"
        case .moveLeft: return "Move the sample left"
        case .done: return "Sweep finished"
        }
    }

    var advice: String {
        switch self {
        case .fixTheImage:
            return "The warning above says what to fix. Saving starts again by itself."
        case .moveLeft(let kept, let total):
            return "Keep moving slowly. Frames save on their own. \(kept) of \(total) saved."
        case .done(let kept, let stoppedEarly):
            return stoppedEarly
                ? "The size limit was reached. \(kept) frames were saved."
                : "\(kept) frames were saved."
        }
    }

    var systemImage: String {
        switch self {
        case .fixTheImage: return "exclamationmark.triangle.fill"
        case .moveLeft: return "arrow.left.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Decides when to keep a frame during a sweep. The helper is never asked to stop or hold
/// still: frames are kept on their own as the slide travels, and saving only pauses while
/// the image is too dark or out of focus.
///
/// Frames replace video because the store holds 50 MB in total: a sweep of stills covers
/// several fields of view for a few MB, where a clip of the same sweep would not fit.
///
/// Shake does not stop a frame being kept. A sweep *is* the slide moving, so a shake warning
/// is expected throughout; what a moving slide must not be is blurred, and the blur check
/// already catches that.
///
/// Pure logic with no camera dependency, so it is unit tested.
final class FrameSweep {
    enum Step: Equatable {
        /// Do nothing with this frame.
        case wait
        /// Keep this frame: it is the next one in the sweep.
        case keepFrame
    }

    let thresholds: SweepThresholds

    private(set) var keptCount = 0
    private(set) var bytesWritten = 0
    private(set) var isFinished = false
    private(set) var prompt: SweepPrompt

    /// How far the view has travelled since the last frame was kept.
    private var shiftSinceLastFrame = 0.0

    init(thresholds: SweepThresholds = SweepThresholds()) {
        self.thresholds = thresholds
        prompt = .moveLeft(kept: 0, of: thresholds.framesPerSweep)
    }

    /// An issue that stops frames being kept. Shake is not one of them.
    static func blocksCapture(_ issue: CaptureIssue?) -> Bool {
        switch issue {
        case .tooDark, .blurry: return true
        case .shaky, nil: return false
        }
    }

    /// Feed one analyzed frame.
    /// - Parameters:
    ///   - isSettled: the quality check has seen enough readings to be trusted.
    ///   - issue: the issue the check is showing, if any.
    ///   - shakePixels: shift between analyzed frames, or nil before the first comparison.
    @discardableResult
    func update(isSettled: Bool, issue: CaptureIssue?, shakePixels: Double?) -> Step {
        guard !isFinished else { return .wait }

        // Count the travel even while saving is paused: the slide may well be moved past a
        // dark or blurred patch, and that ground should not be covered twice.
        if let shake = shakePixels, shake >= thresholds.ignoreShiftBelow {
            shiftSinceLastFrame += shake
        }

        guard isSettled, !Self.blocksCapture(issue) else {
            prompt = .fixTheImage
            return .wait
        }

        // The first frame is kept as soon as the image is good; after that the view has to
        // have travelled, so the same field of view is not kept twice.
        let hasTravelled = keptCount == 0 || shiftSinceLastFrame >= thresholds.shiftBetweenFrames
        guard hasTravelled else {
            prompt = .moveLeft(kept: keptCount, of: thresholds.framesPerSweep)
            return .wait
        }

        keptCount += 1
        shiftSinceLastFrame = 0
        if keptCount >= thresholds.framesPerSweep {
            isFinished = true
            prompt = .done(kept: keptCount, stoppedEarly: false)
        } else {
            prompt = .moveLeft(kept: keptCount, of: thresholds.framesPerSweep)
        }
        return .keepFrame
    }

    /// Call with the size of each frame written. The sweep ends when it reaches the ceiling,
    /// so one sweep cannot fill the store.
    func addWrittenBytes(_ bytes: Int) {
        bytesWritten += bytes
        guard bytesWritten >= thresholds.maxBytes, !isFinished else { return }
        isFinished = true
        prompt = .done(kept: keptCount, stoppedEarly: true)
    }

    func reset() {
        keptCount = 0
        bytesWritten = 0
        shiftSinceLastFrame = 0
        isFinished = false
        prompt = .moveLeft(kept: 0, of: thresholds.framesPerSweep)
    }
}
