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
    /// How many fields the guide bar draws in a row. A row now ends where the helper says
    /// the cover slip ends, so this is only how wide the bar is drawn, not where the sweep
    /// turns.
    var framesPerRow: Int = 4
    /// How far the view has to have moved from the last kept frame before another is kept, in
    /// pixels, so two frames are not taken of the same field of view. `TravelSinceLastFrame`
    /// measures this against the kept frame itself, so a slide pushed back and forth returns
    /// to where it started and has covered no new ground.
    ///
    /// NOT CALIBRATED on a stage, but measured: on 600 frames of microscope footage this kept
    /// 114 frames with a median of 305 px between them, and every pair could still be lined
    /// up. Raising it was tried earlier at 180, 240 and 300 against a running total of
    /// frame-to-frame shifts, and covered less ground rather than more; that total is no
    /// longer what the threshold is measured against, so those runs say nothing about this
    /// number.
    ///
    /// There is a ceiling either way. Frames are lined up by registration, which needs them to
    /// overlap, and `PanoramaStitcher.maxShiftFraction` refuses a pair that has moved more than
    /// 0.4 of a frame, so on a 1080 px wide frame nothing above 432 can be joined at all.
    var shiftBetweenFrames: Double = 120
    /// How far the view has to have moved before the frame that starts a new row is kept.
    ///
    /// A step down is a whole row, not a nudge along one, and the sweep only measures
    /// distance: without this it keeps the first frame of the new row after the same 120 px
    /// as a sideways nudge, which is a hand's width into the step rather than at the end of
    /// it. The prompt then flips to "move left" while the slide is still on its way down, so
    /// the row that follows lies on top of the one before instead of below it.
    ///
    /// PLACEHOLDER, not calibrated. It has the same ceiling as a sideways step and a tighter
    /// one in practice: `PanoramaStitcher.maxShiftFraction` refuses a pair past 0.4 of a
    /// frame, which is 768 px down a 1920 px tall frame, and the frame above has to still be
    /// joinable to the one below it.
    var shiftBetweenRows: Double = 600
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
    /// The row being walked, counted from 1. There is no total: a sweep runs until the
    /// helper reaches the bottom of the cover slip.
    var row: Int
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
            return "Slide it slowly right, to the far edge of the cover slip. Tap At the edge "
                + "when that straight line comes into view. \(kept) of \(total) saved."
        case .move(.down, let kept, let total):
            return "Nudge it down one step, then carry on back the other way. \(kept) of "
                + "\(total) saved."
        case .move(.left, let kept, let total):
            return "Slide it slowly left, to the near edge of the cover slip. Tap At the edge "
                + "when that straight line comes into view. \(kept) of \(total) saved."
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
    /// The row being walked, counted from 1. A row lasts until the helper says the cover
    /// slip edge is in view.
    private(set) var row = 1
    /// Frames kept before this row started, so the guide bar can show how far along it is.
    private var keptWhenRowStarted = 0
    /// Set between the helper reaching the edge and the first frame of the row below.
    private var isTurning = false
    private(set) var bytesWritten = 0
    private(set) var isFinished = false
    private(set) var prompt: SweepPrompt

    init(thresholds: SweepThresholds = SweepThresholds()) {
        self.thresholds = thresholds
        prompt = .move(.right, kept: 0, of: thresholds.framesPerSweep)
    }

    /// Where to send the slide next, given how many frames are already kept. Rows run right,
    /// then left, then right again; between rows the slide goes down one step, and the frame
    /// after that step starts the new row.
    /// Which way to send the slide next. Rows alternate: the first runs right, the one
    /// below it comes back left. A row ends when the helper says the cover slip does.
    var direction: SweepDirection {
        if isTurning { return .down }
        return row.isMultiple(of: 2) ? .left : .right
    }

    /// Called when the helper can see the edge of the cover slip in the view. The next frame
    /// kept starts the row below, however many were kept in this one.
    ///
    /// The app cannot find that edge itself: it is a straight line at the boundary of a
    /// bright field, and nothing here looks for it. The helper is looking right at it.
    func reachedTheEdge() {
        guard !isFinished, keptCount > 0, !isTurning else { return }
        isTurning = true
        prompt = movePrompt
    }

    /// Where the sweep has got to, for the progress bar.
    var progress: SweepProgress {
        SweepProgress(
            kept: keptCount,
            total: max(thresholds.framesPerSweep, 1),
            row: row,
            keptInRow: keptCount - keptWhenRowStarted,
            framesPerRow: max(thresholds.framesPerRow, 1)
        )
    }

    private var movePrompt: SweepPrompt {
        .move(direction, kept: keptCount, of: thresholds.framesPerSweep)
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
    ///   - travel: how far the view has moved from the last kept frame, from
    ///     `TravelSinceLastFrame`. nil when nothing is kept yet, or when the two frames no
    ///     longer have enough in common to be lined up.
    @discardableResult
    func update(isSettled: Bool, issue: CaptureIssue?, shift: CGPoint?, travel: Double?) -> Step {
        guard !isFinished else { return .wait }

        let step = shift.map { hypot($0.x, $0.y) } ?? 0
        // No reading at all once a frame is kept means the view has gone beyond it
        // altogether. Waiting for the distance to reach the mark would then be waiting for a
        // reading that cannot come back, so the next usable frame starts a fresh run. The
        // checks below still apply: a frame kept here has to be worth keeping.
        let outOfReach = keptCount > 0 && travel == nil

        guard isSettled, !Self.blocksCapture(issue) else {
            prompt = .fixTheImage
            return .wait
        }

        // Mid-lurch: the next frame could not be lined up against this one, so it is no use
        // keeping it. The slide is still where it is, so nothing is lost by waiting.
        guard step <= thresholds.maxStepPixels else {
            prompt = movePrompt
            return .wait
        }

        // The first frame is kept as soon as the image is good; after that the view has to
        // have moved away from where the last one was taken, by a row's worth when the next
        // move is the step down between rows.
        guard keptCount == 0 || outOfReach || (travel ?? 0) >= travelWanted
        else {
            prompt = movePrompt
            return .wait
        }

        return keep()
    }

    /// How far the view has to travel before the next frame is kept. A step down between
    /// rows is a whole row; everything else is a nudge along one.
    private var travelWanted: Double {
        direction == .down ? thresholds.shiftBetweenRows : thresholds.shiftBetweenFrames
    }

    private func keep() -> Step {
        keptCount += 1
        if isTurning {
            // This frame is the first of the row below.
            isTurning = false
            row += 1
            keptWhenRowStarted = keptCount - 1
        }
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
        isFinished = false
        row = 1
        keptWhenRowStarted = 0
        isTurning = false
        prompt = .move(.right, kept: 0, of: thresholds.framesPerSweep)
    }
}
