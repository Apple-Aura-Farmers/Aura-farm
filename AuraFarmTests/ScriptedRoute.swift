import CoreGraphics
import XCTest

@testable import AuraFarm

/// A hand-scripted run of `GuidedSweep`, 10 readings a second, in screen axes: the view moves a
/// set step on each reading and every reading says what the box looks like.
final class ScriptedRoute {
    struct Frame {
        var viewClass = ViewClass.sample
        var tracking = TrackingState.tracking
        var ahead: Double? = 400
        var behind: Double? = 400
        var aheadFocus: Double? = 1
        var behindFocus: Double? = 0.95
        var sideA: Double? = 400
        var sideB: Double? = 400
        var still = false
        var speed = 0.05
        /// The screen direction side A's picture lies in; nil keeps a side imbalance a rejection.
        var sideDirection: CGPoint?
        /// The registration box's sharpness, and the quarters in heading terms (nil: not known).
        var box: Double? = 400
        var aheadAway: Double?
        var aheadToward: Double?
        var behindAway: Double?
        var behindToward: Double?
        /// The edge-line detector's result on this reading (nil: not computed).
        var line: EdgeLine?
        /// The heading the line was measured along; nil: the route's own.
        var lineHeading: CGPoint?

        /// Nothing to follow: the tracker is paused over blank glass.
        static let blank = Frame(
            viewClass: .blank, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
            behindFocus: nil, sideA: nil, sideB: nil)
        /// The same with the helper resting on it: an edge is confirmed only at rest.
        static let blankStill = Frame(
            viewClass: .blank, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
            behindFocus: nil, sideA: nil, sideB: nil, still: true)
        /// The half ahead is over the edge, the half behind still sharp.
        static let edgeAhead = Frame(ahead: 50, behind: 300, sideA: 300, sideB: 300, still: true)
    }

    var guide = GuidedSweep()
    /// Seconds the slide has been still in a row, as the indicators count them.
    private var stillRun = 0.0

    /// +1, or -1 for a frame that maps to the guide's axes with a mirror.
    var frameHandedness = 1.0

    init(
        fullCoverSlip: Bool = false, asksEdges: Bool = false,
        configure: (inout GuidedSweepThresholds) -> Void = { _ in }
    ) {
        var thresholds = GuidedSweepThresholds()
        thresholds.fullCoverSlip = fullCoverSlip
        thresholds.asksEdges = asksEdges
        configure(&thresholds)
        guide = GuidedSweep(thresholds: thresholds)
    }
    var seconds = 0.0
    var position = CGPoint.zero
    var steps: [GuideStep] = []
    var returnCount = 0
    var lastReturn = BlankReturnOutcome.none

    var last: GuideStep { steps[steps.count - 1] }
    var instructions: [GuideInstruction] { steps.map(\.instruction) }

    static let left = CGPoint(x: -0.05, y: 0)
    static let up = CGPoint(x: 0, y: -0.1)
    static let right = CGPoint(x: 0.1, y: 0)

    func reading(_ frame: Frame) -> GuideReading {
        stillRun = frame.still ? stillRun + 0.1 : 0
        return GuideReading(
            seconds: seconds, position: position, tracking: frame.tracking, unconfirmedGaps: 0,
            viewClass: frame.viewClass, speedFraction: frame.speed, isStill: frame.still,
            aheadSharpness: frame.ahead, behindSharpness: frame.behind,
            aheadFocusRatio: frame.aheadFocus, behindFocusRatio: frame.behindFocus,
            sideSharpnessA: frame.sideA, sideSharpnessB: frame.sideB, lastBlankReturn: lastReturn,
            blankReturnCount: returnCount, sideADirection: frame.sideDirection,
            boxSharpness: frame.box, quadAheadAway: frame.aheadAway,
            quadAheadToward: frame.aheadToward, quadBehindAway: frame.behindAway,
            quadBehindToward: frame.behindToward, stillSeconds: stillRun, edgeLine: frame.line,
            edgeLineHeading: frame.lineHeading, frameHandedness: frameHandedness)
    }

    func feed(_ frame: Frame = Frame(), move: CGPoint = .zero, times: Int = 1) {
        for _ in 0..<times {
            seconds += 0.1
            position = CGPoint(x: position.x + move.x, y: position.y + move.y)
            steps.append(guide.update(reading(frame)))
        }
    }

    /// The helper's answer about an edge on the next reading, with the view where it is.
    @discardableResult
    func answer(_ feedback: EdgeFeedback, _ frame: Frame = Frame(still: true)) -> GuideStep {
        seconds += 0.1
        let step = guide.userEdge(feedback, reading(frame))
        steps.append(step)
        return step
    }

    /// Presses "Stage limit" on the next reading, with the view where it is.
    @discardableResult
    func pressStageLimit(_ frame: Frame = Frame(still: true)) -> GuideStep {
        seconds += 0.1
        let step = guide.stageLimitReached(reading(frame))
        steps.append(step)
        return step
    }

    /// Moves toward the current target 0.1 field a reading, then holds still on it until the
    /// route answers with a capture or a new state. Returns whether a capture happened.
    @discardableResult
    func visitTarget(maxReadings: Int = 80) -> Bool {
        guard let target = last.target else { return false }
        let captures = guide.placements.count
        for _ in 0..<maxReadings {
            let dx = Double(target.x - position.x)
            let dy = Double(target.y - position.y)
            let length = hypot(dx, dy)
            if length > 0.05 {
                let step = min(0.1, length)
                feed(move: CGPoint(x: dx / length * step, y: dy / length * step))
            } else {
                feed(Frame(still: true))
            }
            if guide.placements.count > captures { return true }
        }
        return false
    }

    /// Travels left onto sample, finds the left edge at the centre cross and takes the first
    /// spot of column 1.
    func startColumnOne() {
        feed(move: Self.left, times: 15)
        feed(Frame(ahead: 50, behind: 250, still: true), times: 24)
        feed(move: Self.right, times: 6)
        feed(Frame(still: true), times: 14)
    }
}
