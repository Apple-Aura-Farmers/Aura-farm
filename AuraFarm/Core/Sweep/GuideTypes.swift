import CoreGraphics
import Foundation

/// How sure the tracker is of the position it reports.
enum TrackingState: Equatable {
    case tracking
    /// NO DETAIL: nothing to follow, the position is frozen.
    case paused
    /// Detail is back and the picture match is still deciding.
    case matching
    case lost
}

/// One reading the guide is fed. Positions are in fields, in screen axes; see `GuidedSweep`.
struct GuideReading: Equatable {
    var seconds: Double
    var position: CGPoint
    var tracking: TrackingState
    /// The pipeline's unmatched blank returns plus its lost gaps so far; a rise means the
    /// position may be off.
    var unconfirmedGaps: Int
    var viewClass: ViewClass
    /// `MovementIndicators.speedFraction`.
    var speedFraction: Double
    /// Frame-to-frame movement under `MovementIndicatorThresholds.stillPixels` for the last
    /// few readings.
    var isStill: Bool
    /// The sharpness of the half of the box the view is travelling toward, and of the half it
    /// is leaving; nil when not known (no heading, no box). See `BoxHalves`.
    var aheadSharpness: Double?
    var behindSharpness: Double?
    /// The focus ratio of the half ahead and of the half behind: its sharpness over the same
    /// content's in the anchor frame (about 1 when unchanged). See `SlideTrackerReading`.
    var aheadFocusRatio: Double?
    var behindFocusRatio: Double?
    /// The sharpness of the two halves ACROSS the heading (left and right on an up or down
    /// leg), in no fixed order; nil when not known. A clear difference means the cover slip's
    /// side is drifting into view, not the end of the leg arriving. See `BoxHalves.sides`.
    var sideSharpnessA: Double?
    var sideSharpnessB: Double?
    /// How the tracker's latest blank return came out, and how many returns it has decided so
    /// far (matched plus unmatched): a rise in the count is a new return.
    var lastBlankReturn = BlankReturnOutcome.none
    var blankReturnCount = 0
    /// The run monitor says focus is clearly low: a spot is not captured yet. See `RunMonitor`.
    var focusLow = false
}

/// How the tracker took the picture back after a stretch with nothing to follow.
enum BlankReturnOutcome: Equatable {
    case none
    /// The held picture was found again: the position is trustworthy.
    case matched
    /// It was not: the position carries on from the frozen one and may be off.
    case unmatched
}

/// What the route made of the edge conditions on one reading, for the CSV. Names, not enums,
/// because that is all the CSV needs.
struct EdgeDiagnostics: Equatable {
    /// "none", "half_edge" or "whole_box".
    var candidate = "none"
    /// "none", "checking", "confirmed" or "blur".
    var verdict = "none"
    /// A short word when something was decided or rejected, else empty: arrived, not_arrived,
    /// vouched, behind_blurred, side_imbalance, halves_too_close, spot_hold, speed_spike,
    /// same_spot, moved, timeout_no_detail.
    var reason = ""
}

/// Why the run is paused: the phone moved off the eyepiece, or the picture went out of focus.
enum GuidePauseReason: Equatable {
    case alignment, focus
}

/// What the guide asks the person to do next.
enum GuideInstruction: Equatable {
    /// No sample seen yet.
    case findSample
    /// Keep turning this way until the sample ends (no stops); unit vector.
    case travel(direction: CGPoint)
    /// The vector from the current position to the target, in fields.
    case move(toward: CGPoint)
    /// The target is beyond `farAwayFields`: the UI pins the cross to the edge with an arrow;
    /// unit vector.
    case farAway(direction: CGPoint)
    /// On target, not still yet.
    case aligned
    /// 0...1 countdown ring.
    case holding(progress: Double)
    case captured
    /// The sample ended here: go back to the last spot with sample.
    case edgeGoBack(toward: CGPoint)
    /// One reading: the edge of the sample is at the centre of the view, so the route moves on
    /// without a trip back.
    case edgeReached
    /// The edge looks reached: checking it is not a blur while the helper holds still.
    case checkingEdge(progress: Double)
    /// Going back did not bring detail back for a while: keep going back, or refocus if it
    /// looks blurry. Same direction as `edgeGoBack`.
    case stillNoDetail(toward: CGPoint)
    /// The view went blank while the helper was moving normally: step back onto the sample
    /// and come forward again, and the arrival decides whether that was the edge. Same
    /// direction as `edgeGoBack`.
    case checkEdge(toward: CGPoint)
    /// The helper said the stage cannot go further: the route turns (see `SlideRoute`).
    case stageLimit
    /// The run is paused until the picture is back; see `RunMonitor`.
    case paused(GuidePauseReason)
    case tooFar
    case otherWay
    case refocus
    case slowDown
    case finished

    /// One short line in plain words, for the lab.
    var debugText: String {
        switch self {
        case .findSample: "Find the sample and focus on it"
        case .travel: "Keep turning until the sample ends"
        case .move: "Turn so the cross reaches the centre"
        case .farAway: "Target is far, follow the arrow"
        case .aligned: "On target, hold still"
        case .holding: "Hold still"
        case .captured: "Captured"
        case .edgeGoBack: "Edge found, go back"
        case .edgeReached: "Edge reached"
        case .checkingEdge: "Checking edge"
        case .stillNoDetail: "Still no detail: go back, or refocus if it looks blurry"
        case .checkEdge: "Check edge: step back"
        case .stageLimit: "Stage limit, turning"
        case .paused(let reason): reason == .alignment ? "Paused: alignment" : "Paused: focus"
        case .tooFar: "Too far, come back a little"
        case .otherWay: "Other way"
        case .refocus: "Refocus"
        case .slowDown: "Slow down"
        case .finished: "Sample finished"
        }
    }

    /// What the helper reads on screen: short, and only about what is drawn (the cross, the
    /// arrow). Unlike `debugText` it may be reworded freely; the CSV uses `csvName`.
    var helperText: String {
        switch self {
        case .findSample: "Move onto the sample and focus"
        case .travel: "Follow the arrow until the edge reaches the centre cross"
        case .move, .farAway: "Bring the cross to the centre"
        case .aligned, .holding: "Hold still"
        case .captured: "Captured"
        case .edgeReached: "Edge reached"
        case .checkingEdge: "Checking edge… hold still"
        case .edgeGoBack: "Edge of the sample. Follow the arrow back"
        case .stillNoDetail: "No detail. Follow the arrow back, or refocus if it's blurry"
        case .checkEdge: "Step back a little, then come forward again"
        case .stageLimit: "Stage limit reached. Turning"
        case .paused(.alignment): "Phone moved. Put it back so the circle fills the outline"
        case .paused(.focus): "Out of focus. Turn the focus knob slowly until it's sharp"
        case .tooFar, .otherWay: "Turn back toward the cross"
        case .refocus: "Refocus"
        case .slowDown: "Slow down"
        case .finished: "Sample finished"
        }
    }

    /// A short word for the CSV.
    var csvName: String {
        switch self {
        case .findSample: "find_sample"
        case .travel: "travel"
        case .move: "move"
        case .farAway: "far_away"
        case .aligned: "aligned"
        case .holding: "holding"
        case .captured: "captured"
        case .edgeGoBack: "edge_go_back"
        case .edgeReached: "edge_reached"
        case .checkingEdge: "checking_edge"
        case .stillNoDetail: "still_no_detail"
        case .checkEdge: "check_edge"
        case .stageLimit: "stage_limit"
        case .paused(let reason): reason == .alignment ? "paused_alignment" : "paused_focus"
        case .tooFar: "too_far"
        case .otherWay: "other_way"
        case .refocus: "refocus"
        case .slowDown: "slow_down"
        case .finished: "finished"
        }
    }
}

/// Where one kept frame was taken.
struct FramePlacement: Codable, Equatable {
    /// The number of the column sweep that took it, from 1, in the order the sweeps began.
    var column: Int
    /// The order of capture, from 1.
    var order: Int
    /// Screen fields.
    var position: CGPoint
    /// True when tracking may have slipped since the column began.
    var uncertain: Bool
}

enum SweepFinishReason: String, Codable {
    case sampleFinished, endedByHelper, storageFull
    /// The stage ran out of travel to the right, so there is no column to step to.
    case stageLimit
}
