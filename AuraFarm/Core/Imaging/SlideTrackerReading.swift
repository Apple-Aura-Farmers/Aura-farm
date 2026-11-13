import CoreGraphics
import Foundation

/// What `SlideTracker` made of one frame: where the view is, and how sure the tracker is.
struct SlideTrackerReading: Equatable {
    /// Brightness, sharpness and contrast inside the box (the whole frame's with no box),
    /// sampled at `SlideTracker.statsStep`.
    var boxStats: FrameStats
    /// This frame's shift from the last, px. nil when this frame was not tracked or gave nothing.
    var frameShift: CGPoint?
    /// The live offset from the anchor as registration returned it, px.
    var anchorOffset: CGPoint?
    /// The offset the odometer was given: measured, or predicted when the measurement
    /// disagreed with the frame-to-frame movement.
    var usedOffset: CGPoint?
    /// Where the view has travelled, px, in the frame's axes.
    var position: CGPoint = .zero
    /// The position in fields: one field is `boxSide`.
    var positionFields: CGPoint = .zero
    /// The side of the registration box in px; the frame's short side with no box.
    var boxSide: Double = 0
    /// The hop distance in use, px.
    var hopLimit: Double = 0
    var hops = 0
    var gaps = 0
    var isLost = false
    var event = HopOdometer.Event.none
    /// `PanoramaStitcher.agreement` at a hop, when it was measured.
    var hopAgreement: Double?
    /// "measured", "predicted", "missing" or "matching".
    var reading = "missing"
    var predictedStreak = 0
    /// False while the box holds too little detail to follow.
    var hasDetail = true
    var blindStretches = 0
    /// Detail returns recovered by matching the held picture, and those that could not be.
    var blankReturnsMatched = 0
    var blankReturnsUnmatched = 0
    /// "matched" or "unmatched" on the frame where a return was decided, else "".
    var blankReturnEvent = ""
    /// Where the reference picture sits against this frame (px), which equals the true change
    /// of position since it was taken. nil when not available.
    var referenceMatch: CGPoint?
    var trueOffReferenceFields: Double?
    /// How far the tracker's position change since the reference is from `referenceMatch`,
    /// in fields.
    var trackerErrorFields: Double?
    /// "none", "out_of_range", "matching" or "confirmed".
    var pictureCheck = "none"

    /// How sure the tracker is of the position, for the guide.
    var trackingState: TrackingState {
        if !hasDetail { return .paused }
        if reading == "matching" { return .matching }
        if isLost { return .lost }
        return .tracking
    }

    /// Stretches where the position may be off: unmatched blank returns plus lost-then-regained.
    var unconfirmedGaps: Int { blankReturnsUnmatched + gaps }

    /// The position as the person sees it on screen, in fields.
    func screenFields(mapping: ScreenMapping, mirrored: Bool) -> CGPoint {
        let onScreen = mapping.onScreen(position, mirrored: mirrored)
        let side = max(boxSide, 1)
        return CGPoint(x: onScreen.x / side, y: onScreen.y / side)
    }
}
