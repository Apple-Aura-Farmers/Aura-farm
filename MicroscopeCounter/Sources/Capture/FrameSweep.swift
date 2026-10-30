import Foundation

/// How a sweep across one sample is paced: how many frames to keep, how the app decides
/// the slide has been moved and has settled again, and how much disk one sweep may use.
///
/// PLACEHOLDERS: none of these are calibrated on a real microscope setup. Set them from
/// pilot footage before relying on them.
struct SweepThresholds {
    /// Frames kept per sweep. Twelve 720p JPEGs come to roughly 4 MB.
    var framesPerSweep: Int = 12
    /// Average shift (pixels) above which the slide counts as being moved by hand.
    var movingShakePixels: Double = 8
    /// Consecutive still, good readings needed after a move before a frame is kept.
    var stillReadingsBeforeCapture: Int = 3
    /// Hard ceiling for one sweep, so a single test cannot fill the store.
    var maxBytes: Int = 6 * 1024 * 1024
}

/// What the helper should be doing right now. The view turns this into one short line.
enum SweepPrompt: Equatable {
    /// The image is not good enough yet, so nothing is being kept.
    case fixTheImage
    /// Hold the slide still; a frame is about to be kept.
    case holdStill(kept: Int, of: Int)
    /// Move the slide to the left, to bring a new part of the sample into view.
    case moveLeft(kept: Int, of: Int)
    /// The sweep is over.
    case done(kept: Int, stoppedEarly: Bool)
}

extension SweepPrompt {
    /// Plain-language copy for a field helper: what to do, not what was measured.
    var title: String {
        switch self {
        case .fixTheImage: return "Waiting for a clear image"
        case .holdStill: return "Hold still"
        case .moveLeft: return "Move the sample left"
        case .done: return "Sweep finished"
        }
    }

    var advice: String {
        switch self {
        case .fixTheImage:
            return "The warning above says what to fix. Nothing is being saved yet."
        case .holdStill(let kept, let total):
            return "Saving frame \(kept + 1) of \(total)."
        case .moveLeft(let kept, let total):
            return "Slide it a little to the left, then hold still. \(kept) of \(total) saved."
        case .done(let kept, let stoppedEarly):
            return stoppedEarly
                ? "The size limit was reached. \(kept) frames were saved."
                : "\(kept) frames were saved."
        }
    }

    var systemImage: String {
        switch self {
        case .fixTheImage: return "hourglass"
        case .holdStill: return "hand.raised"
        case .moveLeft: return "arrow.left.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Walks the helper through one sweep: hold still, keep a frame, move left, repeat.
///
/// Frames replace video because the store holds 50 MB in total: a sweep of stills covers
/// several fields of view for a few MB, where a clip of the same sweep would not fit.
///
/// Pure logic with no camera dependency, so it is unit tested. It is told whether the
/// image is good and how much the view is shifting, and it answers whether to keep the
/// frame in hand.
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
    private(set) var prompt: SweepPrompt

    private enum State {
        /// Waiting for the image to settle before the next frame.
        case settling
        /// A frame was kept; waiting for the helper to move the slide.
        case awaitingMove
        case finished(stoppedEarly: Bool)
    }

    private var state: State = .settling
    private var stillStreak = 0

    init(thresholds: SweepThresholds = SweepThresholds()) {
        self.thresholds = thresholds
        prompt = .holdStill(kept: 0, of: thresholds.framesPerSweep)
    }

    var isFinished: Bool {
        if case .finished = state { return true }
        return false
    }

    /// Feed one analyzed frame.
    /// - Parameters:
    ///   - isImageGood: the quality check has settled with no issue.
    ///   - shakePixels: average shift between analyzed frames, or nil before the first comparison.
    @discardableResult
    func update(isImageGood: Bool, shakePixels: Double?) -> Step {
        switch state {
        case .finished:
            return .wait

        case .awaitingMove:
            // The slide has to visibly move before the next frame, so two frames of the
            // same field of view are not both kept.
            if let shake = shakePixels, shake > thresholds.movingShakePixels {
                state = .settling
                stillStreak = 0
                prompt = .holdStill(kept: keptCount, of: thresholds.framesPerSweep)
            } else {
                prompt = .moveLeft(kept: keptCount, of: thresholds.framesPerSweep)
            }
            return .wait

        case .settling:
            guard isImageGood else {
                stillStreak = 0
                prompt = .fixTheImage
                return .wait
            }
            // A reading before the first comparison counts as still: there is nothing
            // yet to say otherwise.
            let isStill = (shakePixels ?? 0) <= thresholds.movingShakePixels
            guard isStill else {
                stillStreak = 0
                prompt = .holdStill(kept: keptCount, of: thresholds.framesPerSweep)
                return .wait
            }

            stillStreak += 1
            guard stillStreak >= thresholds.stillReadingsBeforeCapture else {
                prompt = .holdStill(kept: keptCount, of: thresholds.framesPerSweep)
                return .wait
            }

            keptCount += 1
            stillStreak = 0
            if keptCount >= thresholds.framesPerSweep {
                state = .finished(stoppedEarly: false)
                prompt = .done(kept: keptCount, stoppedEarly: false)
            } else {
                state = .awaitingMove
                prompt = .moveLeft(kept: keptCount, of: thresholds.framesPerSweep)
            }
            return .keepFrame
        }
    }

    /// Call with the size of each frame written. The sweep ends when it reaches the ceiling,
    /// so one sweep cannot fill the store.
    func addWrittenBytes(_ bytes: Int) {
        bytesWritten += bytes
        guard bytesWritten >= thresholds.maxBytes, !isFinished else { return }
        state = .finished(stoppedEarly: true)
        prompt = .done(kept: keptCount, stoppedEarly: true)
    }

    func reset() {
        keptCount = 0
        bytesWritten = 0
        stillStreak = 0
        state = .settling
        prompt = .holdStill(kept: 0, of: thresholds.framesPerSweep)
    }
}
