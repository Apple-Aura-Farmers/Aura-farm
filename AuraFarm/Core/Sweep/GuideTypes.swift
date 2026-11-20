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
    /// The screen direction (guide axes) the picture of side A lies in; side B is the opposite.
    /// nil when not known, which keeps a side imbalance a rejection. See `SlideRoute`.
    var sideADirection: CGPoint?
    /// The registration box's sharpness now (the tracker's, at its stats step).
    var boxSharpness: Double?
    /// The four quarters' sharpness in heading terms, relative to the low side half across the
    /// heading: ahead or behind, toward the low side or away from it. See `BoxHalves.quarters`.
    var quadAheadAway: Double?
    var quadAheadToward: Double?
    var quadBehindAway: Double?
    var quadBehindToward: Double?
    /// How long the slide has been still, in seconds, in a row (`MovementIndicators.stillSeconds`);
    /// nil when not known, which leaves `isStill` alone to decide. Edges are confirmed only after
    /// `EdgeConfirmationThresholds.confirmSeconds` of it.
    var stillSeconds: Double?
    /// The edge-line detector's result on frames it ran on, nil on the others. Offsets are
    /// along the heading, positive ahead. Used only by the full-cover-slip mode.
    var edgeLine: EdgeLine?
    /// The heading the edge line was measured along (screen unit vector); nil when not known. A
    /// line measured along another heading than the route's current one is ignored.
    var edgeLineHeading: CGPoint?

    /// The detail in the two quarters of the box ahead along the heading over the detail in the two
    /// behind (the `quad_*` columns): near 0 when the area ahead is empty. nil when any quarter or
    /// the heading is unknown, or nothing is behind.
    var areaAheadShare: Double? {
        guard let aa = quadAheadAway, let at = quadAheadToward, let ba = quadBehindAway,
            let bt = quadBehindToward, ba + bt > 1e-9
        else { return nil }
        return (aa + at) / (ba + bt)
    }

    /// Whether the slide has been still for `seconds` in a row. Without `stillSeconds` this is
    /// `isStill`.
    func isStill(for seconds: Double) -> Bool {
        stillSeconds.map { $0 >= seconds - 1e-9 } ?? isStill
    }
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
    /// vouched, behind_blurred, side_imbalance, corner, corner_rejected, halves_too_close, spot_hold, speed_spike,
    /// same_spot, moved, timeout_no_detail.
    var reason = ""
    /// Full-cover-slip mode: "none", "ahead", "attached" or "confirmed"; empty in legacy mode.
    var lineState = ""
    /// How many of the last moving readings with a candidate line were attached to the slide.
    var lineAttachedCount = 0
    /// The line is attached and at the cross: the stage where the helper may be asked.
    var lineAtCross = false
    /// An edge may be marked here (the route has a heading along which an edge is looked for).
    var canMarkEdge = false
    /// "auto" on the reading where the rule confirmed an edge by itself.
    var feedback = ""
    /// "line" in full-cover-slip mode, "legacy" otherwise.
    var edgeMode = "legacy"
    /// The box's sharpness over the median before the candidate began, when the corner rule
    /// looked at it; nil otherwise.
    var cornerBoxShare: Double?
    /// Which rule accepted the latest edge line ("strict" or "area"); empty without one.
    var lineAccept = ""
    /// The detail ahead over the detail behind on this reading (`GuideReading.areaAheadShare`).
    var areaAheadShare: Double?
    /// The predicted edge's position along the current leg's heading at the column's x, in fields;
    /// nil without a prediction.
    var predictedEdgeAlong: Double?
    /// "Edge should be here. Confirm?" is showing.
    var expectedEdgeAsk = false
    /// How many times the current edge line was passed without confirming, and its slide position
    /// along the leg; nil without a line being counted.
    var lineCrossings = 0
    var lineAlong: Double?
}

/// The helper's answer about an edge, in full-cover-slip mode.
enum EdgeFeedback: Equatable {
    /// "✓ Edge": the line at the cross is the edge.
    case yes
    /// "✗ Not an edge": it is not; the route keeps going.
    case no
    /// "Mark edge here": an edge the rule missed, at the cross.
    case mark

    /// The word written in the CSV's `edge_feedback` column.
    var csvName: String {
        switch self {
        case .yes: "yes"
        case .no: "no"
        case .mark: "mark"
        }
    }
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
    /// Full-cover-slip mode: a line that may be the edge is ahead; keep going until it reaches
    /// the centre cross.
    case lineAhead
    /// Full-cover-slip mode: the line is attached and at the cross. Stay still: the rule confirms it
    /// after `confirmSeconds`, or the helper is asked.
    case edgeDetected
    /// Full-cover-slip mode: a line that passes the rule is just behind the cross (the helper went
    /// past it): come back along the leg until it is on the cross; unit vector or the way back.
    case edgeBehind(toward: CGPoint)
    /// An accepted edge line is a little ahead (0 to `lineLeadFields`) but the spot rules call the
    /// view too far or the wrong way: keep going along the leg. `nudge` after the helper has been
    /// still for a while with the line beyond the at-cross band.
    case lineLead(direction: CGPoint, nudge: Bool)
    /// The view passed the predicted edge with nothing ahead and no edge found: ✓ takes it as the
    /// edge, ✗ keeps going.
    case expectedEdge
    /// The helper said the line is not an edge: keep going (shown for a moment).
    case notAnEdge
    /// Full-cover-slip mode: the box has no detail, which says nothing about an edge.
    case nothingToFollow
    case tooFar
    case otherWay
    /// Brief-touch mode: the view went past a spot without touching it; unit vector back to it.
    case missedSpot(toward: CGPoint)
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
        case .lineAhead: "Edge line ahead"
        case .edgeDetected: "Stay still, edge detected"
        case .edgeBehind: "Edge just behind, come back"
        case .lineLead: "A little further, to the line"
        case .expectedEdge: "Edge should be here. Confirm?"
        case .notAnEdge: "Not an edge, keep going"
        case .nothingToFollow: "Nothing to follow here"
        case .stageLimit: "Stage limit, turning"
        case .paused(let reason): reason == .alignment ? "Paused: alignment" : "Paused: focus"
        case .tooFar: "Too far, come back a little"
        case .otherWay: "Other way"
        case .missedSpot: "Missed spot"
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
        case .lineAhead: "Edge line ahead. Keep going until it reaches the centre cross"
        case .edgeDetected: "Stay still, edge detected"
        case .edgeBehind: "Edge just behind you. Come back until it's on the cross"
        case .lineLead: "A little further, to the line"
        case .expectedEdge: "Edge should be here. Confirm?"
        case .notAnEdge: "Not an edge. Keep going"
        case .nothingToFollow:
            "Nothing to follow here. Turn back, or move to a patch with more particles"
        case .stageLimit: "Stage limit reached. Turning"
        // No words: the orange circle and "Paused" say it, and the picture stays clear.
        case .paused(.alignment): ""
        case .paused(.focus): "Out of focus. Turn the focus knob slowly until it's sharp"
        case .tooFar, .otherWay: "Turn back toward the cross"
        case .missedSpot: "Missed a spot. Come back a little, slower"
        case .refocus: "Refocus"
        case .slowDown: "Slow down"
        case .finished: "Sample finished"
        }
    }

    /// `helperText`, with the words for full-cover-slip mode: there a blank box means the edge
    /// line is out of view, so the helper steps back until it is in view.
    func helperText(fullCoverSlip: Bool) -> String {
        if fullCoverSlip, case .checkEdge = self { return "Step back until the edge line is in view" }
        return helperText
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
        case .lineAhead: "line_ahead"
        case .edgeDetected: "edge_detected"
        case .edgeBehind: "edge_behind"
        case .lineLead: "line_ahead"
        case .expectedEdge: "expected_edge"
        case .notAnEdge: "not_an_edge"
        case .nothingToFollow: "nothing_to_follow"
        case .stageLimit: "stage_limit"
        case .paused(let reason): reason == .alignment ? "paused_alignment" : "paused_focus"
        case .tooFar: "too_far"
        case .otherWay: "other_way"
        case .missedSpot: "missed_spot"
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
    /// Full-cover-slip mode: a step right found the right edge line (or blank), so the last
    /// column is done.
    case rightEdge
}
