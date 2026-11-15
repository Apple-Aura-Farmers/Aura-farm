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
}
