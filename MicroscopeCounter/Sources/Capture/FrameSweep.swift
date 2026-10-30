import CoreGraphics
import Foundation

/// How a sweep across one sample is paced: how many frames to keep, how far the view has to
/// travel between them, and how much disk one sweep may use.
///
/// PLACEHOLDERS: none of these are calibrated on a real microscope setup. Set them from
/// pilot footage before relying on them.
struct SweepThresholds {
    /// Frames kept per sweep. Twelve 720p JPEGs come to roughly 4 MB.
    var framesPerSweep: Int = 12
    /// Frames along one row before the sweep turns down and comes back the other way.
    var framesPerRow: Int = 4
    /// How far the view has to have actually moved from the last frame before another is
    /// kept, in pixels, so two frames are not taken of the same field of view. This is a
    /// distance from where the last frame was, not a total of wandering about: a slide pushed
    /// back and forth returns to where it started and has covered no new ground.
    var shiftBetweenFrames: Double = 120
    /// A single reading below this is treated as the mount wobbling rather than the slide
    /// moving, and is ignored.
    var ignoreShiftBelow: Double = 3
    /// A single reading above this means the slide was moved faster than frames can be placed
    /// against each other. Such a frame is not kept, because the next one could not be lined
    /// up with it; the sweep waits for the slide to be moved at a workable speed.
    var maxStepPixels: Double = 150
    /// Hard ceiling for one sweep, so a single test cannot fill the store.
    var maxBytes: Int = 6 * 1024 * 1024
}

/// The way to move the slide next. The sweep walks it in rows: across, down one step, back
/// the other way, so the frames cover a block of the slide instead of a single line.
enum SweepDirection: String, Equatable {
    case right
    case down
    case left
}

/// How far along the sweep is, for the progress the helper watches while moving the slide.
struct SweepProgress: Equatable {
    var kept: Int
    var total: Int
    /// The row being walked, counted from 1.
    var row: Int
    var rowCount: Int
    /// Frames kept so far in this row, and how many it holds.
    var keptInRow: Int
    var framesPerRow: Int

    /// 0 to 1 across the whole sweep.
    var fraction: Double { total > 0 ? Double(kept) / Double(total) : 0 }
}

/// What the helper should know right now. The view turns this into one short line.
enum SweepPrompt: Equatable {
    /// Something is wrong with the image, so nothing is being kept until it is fixed.
    case fixTheImage
    /// Move the slide this way; frames are saving by themselves.
    case move(SweepDirection, kept: Int, of: Int)
    /// The sweep is over.
    case done(kept: Int, stoppedEarly: Bool)
}

extension SweepPrompt {
    /// Plain-language copy for a field helper: what to do, not what was measured.
    var title: String {
        switch self {
        case .fixTheImage: return "Paused"
        case .move(.right, _, _): return "Move the sample right"
        case .move(.down, _, _): return "Move the sample down"
        case .move(.left, _, _): return "Move the sample left"
        case .done: return "Sweep finished"
        }
    }

    var advice: String {
        switch self {
        case .fixTheImage:
            return "The warning above says what to fix. Saving starts again by itself."
        case .move(.right, let kept, let total):
            return "Slide it slowly to the right. Frames save on their own. \(kept) of \(total) saved."
        case .move(.down, let kept, let total):
            return "Nudge it down one step, then carry on the other way. \(kept) of \(total) saved."
        case .move(.left, let kept, let total):
            return "Slide it slowly to the left. Frames save on their own. \(kept) of \(total) saved."
        case .done(let kept, let stoppedEarly):
            return stoppedEarly
                ? "The size limit was reached. \(kept) frames were saved."
                : "\(kept) frames were saved."
        }
    }

    var systemImage: String {
        switch self {
        case .fixTheImage: return "exclamationmark.triangle.fill"
        case .move(.right, _, _): return "arrow.right.circle.fill"
        case .move(.down, _, _): return "arrow.down.circle.fill"
        case .move(.left, _, _): return "arrow.left.circle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }
}

/// Decides when to keep a frame during a sweep. The helper is never asked to stop or hold
/// still: frames are kept on their own as the slide travels, and saving only pauses while
/// the image is too dark or out of focus.
///
/// The helper is walked across the slide in rows: a few frames to the right, one step down,
/// then back to the left, and so on. That covers a block of the slide rather than a single
/// line, and the picture the frames are joined into takes its shape from the path.
///
/// Nothing here checks that the slide actually went the way it was asked to. The travel that
/// spaces frames apart is a distance, not a direction. What the panorama shows is where the
/// frames really landed, worked out from the frames themselves, so a wrong turn shows up in
/// the picture rather than being hidden by it.
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

    /// Where the view has got to since the last frame was kept, as a distance and direction
    /// from it.
    private var offsetSinceLastFrame = CGPoint.zero

    init(thresholds: SweepThresholds = SweepThresholds()) {
        self.thresholds = thresholds
        prompt = .move(.right, kept: 0, of: thresholds.framesPerSweep)
    }

    /// Where to send the slide next, given how many frames are already kept. Rows run right,
    /// then left, then right again; between rows the slide goes down one step, and the frame
    /// after that step starts the new row.
    static func direction(afterKeeping kept: Int, framesPerRow: Int) -> SweepDirection {
        guard framesPerRow > 0 else { return .right }
        if kept > 0, kept % framesPerRow == 0 { return .down }
        return (kept / framesPerRow) % 2 == 0 ? .right : .left
    }

    /// Where the sweep has got to, for the progress bar.
    var progress: SweepProgress {
        let perRow = max(thresholds.framesPerRow, 1)
        let total = max(thresholds.framesPerSweep, 1)
        return SweepProgress(
            kept: keptCount,
            total: total,
            row: min(keptCount / perRow + 1, (total + perRow - 1) / perRow),
            rowCount: (total + perRow - 1) / perRow,
            keptInRow: keptCount % perRow,
            framesPerRow: perRow
        )
    }

    private var movePrompt: SweepPrompt {
        .move(
            Self.direction(afterKeeping: keptCount, framesPerRow: thresholds.framesPerRow),
            kept: keptCount,
            of: thresholds.framesPerSweep
        )
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
    ///   - shift: how far and which way the view moved since the frame before, or nil before
    ///     the first comparison.
    @discardableResult
    func update(isSettled: Bool, issue: CaptureIssue?, shift: CGPoint?) -> Step {
        guard !isFinished else { return .wait }

        let step = shift.map { hypot($0.x, $0.y) } ?? 0
        // Follow the view even while saving is paused: the slide may well be moved past a dark
        // or blurred patch, and that ground should not have to be covered again.
        if let shift, step >= thresholds.ignoreShiftBelow {
            offsetSinceLastFrame.x += shift.x
            offsetSinceLastFrame.y += shift.y
        }

        guard isSettled, !Self.blocksCapture(issue) else {
            prompt = .fixTheImage
            return .wait
        }

        // Mid-lurch: the next frame could not be lined up against this one, so it is no use
        // keeping it. The travel still counts, so nothing is lost by waiting.
        guard step <= thresholds.maxStepPixels else {
            prompt = movePrompt
            return .wait
        }

        // The first frame is kept as soon as the image is good; after that the view has to
        // have moved away from where the last one was taken.
        let travelled = hypot(offsetSinceLastFrame.x, offsetSinceLastFrame.y)
        guard keptCount == 0 || travelled >= thresholds.shiftBetweenFrames else {
            prompt = movePrompt
            return .wait
        }

        keptCount += 1
        offsetSinceLastFrame = .zero
        if keptCount >= thresholds.framesPerSweep {
            isFinished = true
            prompt = .done(kept: keptCount, stoppedEarly: false)
        } else {
            prompt = movePrompt
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
        offsetSinceLastFrame = .zero
        isFinished = false
        prompt = .move(.right, kept: 0, of: thresholds.framesPerSweep)
    }
}
