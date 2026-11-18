import CoreGraphics
import Foundation

/// The guide's columns in the CSV for one row.
struct GuideRowFields: Equatable {
    var viewClass: String
    var state: String
    var instruction: String
    var targetDx: Double?
    var targetDy: Double?
    var captures: Int
    /// The manual mapping the axes in use are nearest to: "rotateLeft", "asIs-mirrored", ...
    var axesMapping = ""
    /// What the route made of the edge conditions: see `EdgeDiagnostics`.
    var edgeCandidate = "none"
    var edgeVerdict = "none"
    var edgeReason = ""
    /// The sharpness of the two halves across the heading that the route used.
    var sideSharpA: Double?
    var sideSharpB: Double?
    /// The quarters in heading terms (see `BoxHalves.quarters`) and the corner rule's box share.
    var quadAheadAway: Double?
    var quadAheadToward: Double?
    var quadBehindAway: Double?
    var quadBehindToward: Double?
    var cornerBoxShare: Double?
    /// Full-cover-slip mode: how far the edge line has got, and the mode ("line" or "legacy").
    var lineState = ""
    var lineAttachedCount = 0
    var edgeMode = "legacy"
    /// Full-cover-slip mode: the line is attached and at the cross, and an edge may be marked.
    var lineAtCross = false
    var canMarkEdge = false
    /// "auto" when the rule confirmed an edge by itself.
    var edgeFeedback = ""
    /// Spot confirmation (see `BriefTouchThresholds`) and the coverage step, for the CSV.
    var spotMode = ""
    var spotWindow = ""
    var touchSeconds: Double?
    var missedSpots = 0
    var coverageStep = 0.8
    var countingActive = false
    var column = 0
    /// The rule that accepted the latest edge line, the detail ahead over behind, the predicted
    /// edge's position and whether the expected-edge ask shows (see `EdgeDiagnostics`).
    var lineAccept = ""
    var areaAheadShare: Double?
    var predictedEdgeAlong: Double?
    var expectedEdgeAsk = false
}

/// How the preview shows the box, measured from the live preview layer on the main thread.
struct GuideScreenGeometry: Equatable {
    var axes: GuideScreenAxes
    /// The box centre on screen, in points.
    var centre: CGPoint
    /// The box's on-screen side, in points: one field.
    var pointsPerField: Double
    /// The radius of the field on screen, in points; arrows are pinned just inside it.
    var fieldRadius: Double

    /// Whether `other` gives the dry run the same positions in fields: the axes in points per
    /// frame pixel, over points per field, are the same. Showing the picture larger or shifted
    /// (centring the field) scales the axes and the field together and changes nothing; a
    /// turned preview, a new box or a new frame size does.
    func givesSamePositions(as other: GuideScreenGeometry) -> Bool {
        let own = [axes.a, axes.b, axes.c, axes.d].map { $0 / pointsPerField }
        let theirs = [other.axes.a, other.axes.b, other.axes.c, other.axes.d].map {
            $0 / other.pointsPerField
        }
        return zip(own, theirs).allSatisfy { abs($0 - $1) <= 0.01 * max(abs($0), abs($1), 1e-6) }
    }
}

/// What one guide update gives the lab.
struct GuideDryRunResult {
    var fields: GuideRowFields
    var info: SlideMovementInfo.Guide
    /// nil without a preview to draw on (a recorded video).
    var overlay: GuideOverlayModel?
    /// A capture and the target, in the trail's space (frame axes, in fields).
    var captureTrailPoint: CGPoint?
    var targetTrailPoint: CGPoint?
    /// The predicted edges as segments in the trail's space.
    var predictedTrailLines: [PredictedTrailLine] = []
    /// The confirmed edge points, in the trail's space.
    var edgeTrailPoints: [CGPoint] = []
}

/// One predicted edge segment for the trail mini-map.
struct PredictedTrailLine: Equatable {
    enum Kind: Equatable { case top, bottom, left, right }
    var kind: Kind
    var from: CGPoint
    var to: CGPoint
}

/// The lab's "Cover slip" setting: a square slip (the usual 22 x 22 mm) lets the guide predict
/// the right edge from the top and bottom ones; with an unknown shape it does not.
enum CoverSlipShape: String, CaseIterable, Identifiable {
    case square, unknown
    var id: String { rawValue }
    var title: String { self == .square ? "Square" : "Unknown" }
}

/// Feeds `ViewClassifier` and `GuidedSweep` from the lab's steps, so the team can try the
/// guide on the microscope before it has a screen of its own. Nothing is saved as a sweep
/// and no frames are written. Analysis queue only.
///
/// The tracker's position is the content's displacement, so the guide's position (where the
/// VIEW is) is its negation through the axes of the content's motion on screen.
final class GuideDryRun {
    /// How the lab shows the frame's axes on screen, from the picker. Used only when there
    /// is no preview geometry to measure the axes from.
    var mapping = ScreenMapping.asIs
    var mirrored = false
    var geometry: GuideScreenGeometry?
    /// Why the run monitor wants the guide paused; nil to run. Set before each `update`.
    var pauseReason: GuidePauseReason?
    /// The run monitor says focus is clearly low; set before each `update`.
    var focusLow = false
    /// The helper pressed Stage limit: the next update feeds it to the route.
    var stageLimitPressed = false
    /// What the box looked like on the last update, for the run monitor.
    private(set) var lastViewClass = ViewClass.blank
    private(set) var stageLimitCount = 0
    /// The direction an edge line is looked for along (`GuidedSweep.edgeHeading`, screen unit
    /// vector), after the last update; nil while no edge is looked for.
    private(set) var lastEdgeHeading: CGPoint?
    /// The same as a frame vector, for the edge-line detector; nil without a heading or axes.
    var frameHeading: CGPoint? {
        lastEdgeHeading.flatMap { axes.frameVector(ofScreenVector: $0) }
    }
    /// The last reading handed to the guide, for the helper's edge buttons.
    private var lastReading: GuideReading?

    private var classifier = ViewClassifier()
    private var guide = GuidedSweep()
    /// The eyepiece circle's radius has been handed to the guide for this run.
    private var sideInsetApplied = false
    /// How far the first and last columns sit inside the side edges; nil until the circle is known.
    var sideInsetFields: Double? { sideInsetApplied ? guide.sideInsetFields : nil }

    init() { reset() }
    /// Full-cover-slip mode (edges from the line only); changing it starts the guide afresh.
    var fullCoverSlip = false {
        didSet { if fullCoverSlip != oldValue { reset() } }
    }
    /// Full-cover-slip mode: the rule waits for the helper's tap instead of confirming itself.
    var asksEdges = true {
        didSet { if asksEdges != oldValue { reset() } }
    }
    /// The cover slip's shape ("Cover slip"); changing it starts the guide afresh.
    var coverSlip = CoverSlipShape.square {
        didSet { if coverSlip != oldValue { reset() } }
    }
    /// How a spot is ticked: the lab's default is the brief touch; changing it starts afresh.
    var spotMode = SpotConfirmMode.briefTouch {
        didSet { if spotMode != oldValue { reset() } }
    }
    /// Fields between columns (0.8, 1.6 or 2.4); changing it starts afresh.
    var coverageStep = GuidedSweepThresholds().columnSpacingFields {
        didSet { if coverageStep != oldValue { reset() } }
    }
    /// The guide's answer to the last update, for the lab's run summary and counting.
    private(set) var isFinished = false
    private(set) var finishReason: SweepFinishReason?
    private(set) var countingActive = false
    private(set) var column = 0
    private(set) var pendingEnd = false
    private(set) var columnInProgress = false
    private(set) var missedSpots = 0
    private(set) var spotsTicked = 0
    private(set) var edgeSpanFields: Double?
    /// The reading fed to the guide last: where counting needs the view.
    private(set) var lastGuidePosition = CGPoint.zero
    /// The edge line's state after the last update, for the overlay.
    private(set) var lineState = ""
    private let alignTolerance = GuidedSweepThresholds().alignment.alignToleranceFields
    private(set) var captureCount = 0
    private(set) var edgeCount = 0
    private(set) var wrongWayCount = 0
    /// Entries into "A little further" with a nudge (the haptic), and how the right edge was
    /// found, for the run record.
    private(set) var nudgeCount = 0
    private(set) var rightEdgeSource = ""
    private(set) var edgeReachedCount = 0
    private var lastInstruction: GuideInstruction?
    /// Where the guide last sent the view (a screen unit vector), to work out which half of
    /// the box the next content comes into.
    private var lastHeading: CGPoint?
    /// The tracker's blank return totals at the last update, to see a new return and which
    /// way it went.
    private var previousReturns = (matched: 0, unmatched: 0)
    private var lastReturn = BlankReturnOutcome.none
    /// When the instruction became one that moves the view (move, travel, far away).
    private var movingInstructionSince: Double?
    private let hintSeconds = GuidedSweepThresholds().stageLimitHintSeconds

    /// The axes of the content's motion on screen: measured from the preview, or the
    /// picker's mapping (which describes the view's travel) negated.
    private var axes: GuideScreenAxes {
        geometry?.axes
            ?? GuideScreenAxes.from(mapping, mirrored: mirrored, pointsPerPixel: 1).viewTravel
    }

    /// Where the view is, in the guide's screen fields: the tracker's pixels through the
    /// axes, divided by the on-screen size of one field.
    func guidePosition(for step: SlideMovementStep) -> CGPoint {
        axes.guideFields(
            forTrackerPosition: step.position,
            pointsPerField: geometry?.pointsPerField ?? max(step.boxSide, 1))
    }

    /// Feeds one lab step; returns the CSV fields and the info for the screen.
    func update(
        step: SlideMovementStep, indicators: MovementIndicators, seconds: Double,
        edgeLine: EdgeLine? = nil
    ) -> GuideDryRunResult {
        let viewClass = classifier.update(
            brightness: step.boxStats.brightness, sharpness: step.boxStats.sharpness,
            contrast: step.boxStats.contrast)
        lastViewClass = viewClass

        // The position in screen fields: the tracker's pixels through the axes, divided by
        // the on-screen size of one field. Without a preview the picker's mapping stands in,
        // with a field being the box's side in pixels.
        let boxSide = max(step.boxSide, 1)
        // The confirmed eyepiece circle, in the guide's unit (the box side), before the first
        // column: the first and last columns then sit that far plus a margin inside the sides.
        if !sideInsetApplied, guide.columnNumber == 0,
            let circle = step.fieldState?.mask.flatMap({ FieldCircle(fitting: $0) })
        {
            guide.setEyepieceRadius(fields: Double(circle.radius) / boxSide)
            sideInsetApplied = true
        }
        // The axes of the CONTENT's motion on screen: measured from the preview, or the
        // picker's mapping (which describes the view's travel) negated.
        let axes = self.axes
        let pointsPerField = geometry?.pointsPerField ?? boxSide
        let position = axes.guideFields(
            forTrackerPosition: step.position, pointsPerField: pointsPerField)
        let tracking = step.tracking.trackingState

        // The half of the box the view is travelling toward. `axes` map a frame vector to the
        // screen, so the frame direction that shows as the heading is its inverse; new
        // content comes into view on that side of the box.
        var ahead: Double?
        var behind: Double?
        if let heading = lastHeading, let halves = step.tracking.halfSharpness,
            let frameDirection = axes.frameVector(ofScreenVector: heading),
            let pair = halves.aheadAndBehind(forFrameDirection: frameDirection)
        {
            (ahead, behind) = (pair.ahead, pair.behind)
        }
        var aheadFocus: Double?
        var behindFocus: Double?
        if let heading = lastHeading, let ratios = step.tracking.halfFocusRatio,
            let frameDirection = axes.frameVector(ofScreenVector: heading),
            let pair = ratios.aheadAndBehind(forFrameDirection: frameDirection)
        {
            (aheadFocus, behindFocus) = (pair.ahead, pair.behind)
        }
        var sideA: Double?
        var sideB: Double?
        var sideADirection: CGPoint?
        var quads: (aheadAway: Double, aheadToward: Double, behindAway: Double, behindToward: Double)?
        if let heading = lastHeading, let halves = step.tracking.halfSharpness,
            let frameDirection = axes.frameVector(ofScreenVector: heading),
            let sides = halves.sideSharpness(forFrameDirection: frameDirection)
        {
            (sideA, sideB) = sides
            // Where side A's picture lies on screen (the content axes map a frame vector).
            if let pair = BoxHalves.sides(forFrameDirection: frameDirection) {
                quads = halves.quarters(
                    forFrameDirection: frameDirection, lowSide: sides.a < sides.b ? pair.0 : pair.1)
                let screen = axes.screenVector(ofFrameVector: BoxHalves.frameVector(of: pair.0))
                let length = hypot(Double(screen.x), Double(screen.y))
                if length > 1e-9 {
                    sideADirection = CGPoint(x: Double(screen.x) / length, y: Double(screen.y) / length)
                }
            }
        }
        let returns = (
            matched: step.tracking.blankReturnsMatched,
            unmatched: step.tracking.blankReturnsUnmatched
        )
        if returns.matched > previousReturns.matched {
            lastReturn = .matched
        } else if returns.unmatched > previousReturns.unmatched {
            lastReturn = .unmatched
        }
        previousReturns = returns
        if pauseReason != guide.pauseReason {
            if let pauseReason { guide.pause(pauseReason) } else { guide.resume(seconds: seconds) }
        }
        let guideReading = GuideReading(
            seconds: seconds, position: position, tracking: tracking,
            unconfirmedGaps: step.tracking.unconfirmedGaps, viewClass: viewClass,
            speedFraction: indicators.speedFraction, isStill: indicators.stillSeconds > 0,
            aheadSharpness: ahead, behindSharpness: behind, aheadFocusRatio: aheadFocus,
            behindFocusRatio: behindFocus, sideSharpnessA: sideA, sideSharpnessB: sideB,
            lastBlankReturn: lastReturn, blankReturnCount: returns.matched + returns.unmatched,
            focusLow: focusLow, sideADirection: sideADirection,
            boxSharpness: step.boxStats.sharpness, quadAheadAway: quads?.aheadAway,
            quadAheadToward: quads?.aheadToward, quadBehindAway: quads?.behindAway,
            quadBehindToward: quads?.behindToward, stillSeconds: indicators.stillSeconds,
            edgeLine: edgeLine, edgeLineHeading: lastEdgeHeading)
        lastReading = guideReading
        lastGuidePosition = position
        let result: GuideStep
        if stageLimitPressed {
            stageLimitPressed = false
            stageLimitCount += 1
            result = guide.stageLimitReached(guideReading)
        } else {
            result = guide.update(guideReading)
        }
        switch result.instruction {
        case .move, .travel, .farAway: movingInstructionSince = movingInstructionSince ?? seconds
        default: movingInstructionSince = nil
        }
        let showsHint = movingInstructionSince.map { seconds - $0 >= hintSeconds } ?? false
        lastHeading = guide.heading
        if case .edgeReached = result.instruction { edgeReachedCount += 1 }

        if result.capture != nil { captureCount += 1 }
        if case .edgeGoBack = result.instruction {
            if case .edgeGoBack? = lastInstruction {} else { edgeCount += 1 }
        }
        if Self.isWrongWay(result.instruction), !Self.isWrongWay(lastInstruction) {
            wrongWayCount += 1
        }
        if case .lineLead(_, true) = result.instruction {
            if case .lineLead(_, true)? = lastInstruction {} else { nudgeCount += 1 }
        }
        lastInstruction = result.instruction
        rightEdgeSource = guide.rightEdgeSource
        isFinished = guide.isFinished
        finishReason = guide.finishReason
        countingActive = guide.countingActive
        column = guide.columnNumber
        pendingEnd = guide.pendingEnd
        columnInProgress = guide.columnInProgress
        missedSpots = guide.missedSpots
        spotsTicked = guide.placements.count
        edgeSpanFields = guide.edgeSpanFields
        lineState = result.edge.lineState
        lastEdgeHeading = guide.edgeHeading

        let dx = result.target.map { Double($0.x - position.x) }
        let dy = result.target.map { Double($0.y - position.y) }
        let captures = guide.placements.count

        // The picker describes how the VIEW's travel appears on screen: compare with that.
        let closest = axes.viewTravel.closestMapping()
        let axesMapping = closest.mapping.rawValue + (closest.mirrored ? "-mirrored" : "")
        var axesLine = ""
        if geometry != nil {
            axesLine =
                "Axes from preview match: \(closest.mapping.title)"
                + (closest.mirrored ? ", mirrored" : "")
        }
        let differs = geometry != nil && (closest.mapping != mapping || closest.mirrored != mirrored)

        var overlay: GuideOverlayModel?
        if let geometry {
            overlay = GuideOverlayModel.make(
                step: result, position: position, tracking: tracking, centre: geometry.centre,
                pointsPerField: pointsPerField, fieldRadius: geometry.fieldRadius,
                alignToleranceFields: alignTolerance, heading: guide.heading ?? lastHeading)
            // Brief touch: close to the cross but faster than a touch counts.
            overlay?.easeOff =
                spotMode == .briefTouch && !result.isFinished
                && guide.distanceToSpot <= Self.easeOffFields
                && indicators.speedFraction > briefThresholds.maxTouchSpeedFraction
        }
        // A guide point back into the tracker's space (content displacement): the view travels
        // the opposite way, so the offset is subtracted.
        func trailPoint(_ point: CGPoint) -> CGPoint? {
            axes.frameVector(
                ofScreenVector: CGPoint(
                    x: Double(point.x - position.x) * pointsPerField,
                    y: Double(point.y - position.y) * pointsPerField)
            ).map {
                CGPoint(
                    x: step.positionFields.x - $0.x / boxSide,
                    y: step.positionFields.y - $0.y / boxSide)
            }
        }
        let targetPoint = result.target.flatMap(trailPoint)
        let predictedLines = Self.predictedSegments(guide.predictedEdges).compactMap {
            segment -> PredictedTrailLine? in
            guard let from = trailPoint(segment.from), let to = trailPoint(segment.to) else {
                return nil
            }
            return PredictedTrailLine(kind: segment.kind, from: from, to: to)
        }
        return GuideDryRunResult(
            fields: GuideRowFields(
                viewClass: viewClass.rawValue, state: result.stateName,
                instruction: result.instruction.csvName, targetDx: dx, targetDy: dy,
                captures: captures, axesMapping: axesMapping,
                edgeCandidate: result.edge.candidate, edgeVerdict: result.edge.verdict,
                edgeReason: result.edge.reason, sideSharpA: sideA, sideSharpB: sideB,
                quadAheadAway: quads?.aheadAway, quadAheadToward: quads?.aheadToward,
                quadBehindAway: quads?.behindAway, quadBehindToward: quads?.behindToward,
                cornerBoxShare: result.edge.cornerBoxShare, lineState: result.edge.lineState,
                lineAttachedCount: result.edge.lineAttachedCount, edgeMode: result.edge.edgeMode,
                lineAtCross: result.edge.lineAtCross, canMarkEdge: result.edge.canMarkEdge,
                edgeFeedback: result.edge.feedback, spotMode: spotModeName,
                spotWindow: spotMode == .briefTouch ? (guide.spotWindow?.rawValue ?? "") : "",
                touchSeconds: spotMode == .briefTouch ? guide.touchElapsed : nil,
                missedSpots: guide.missedSpots, coverageStep: coverageStep,
                countingActive: guide.countingActive, column: guide.columnNumber,
                lineAccept: result.edge.lineAccept, areaAheadShare: result.edge.areaAheadShare,
                predictedEdgeAlong: result.edge.predictedEdgeAlong,
                expectedEdgeAsk: result.edge.expectedEdgeAsk),
            info: SlideMovementInfo.Guide(
                isOn: true, instruction: result.instruction.debugText, state: result.stateName,
                targetDx: dx, targetDy: dy, viewClass: viewClass.rawValue, captures: captures,
                captureCount: captureCount, edgeCount: edgeCount, isFinished: result.isFinished,
                wrongWayCount: wrongWayCount, nudgeCount: nudgeCount,
                edgeReachedCount: edgeReachedCount, axesLine: axesLine,
                axesDiffer: differs, showsStageLimitHint: showsHint,
                stageLimitCount: stageLimitCount, pendingEnd: guide.pendingEnd,
                columnInProgress: guide.columnInProgress, spotMode: spotMode,
                column: guide.columnNumber, lastColumn: result.lastColumn,
                slipHeightFields: guide.measuredHeightFields,
                sideInsetFields: sideInsetFields),
            overlay: overlay,
            captureTrailPoint: result.capture == nil ? nil : step.positionFields,
            targetTrailPoint: targetPoint, predictedTrailLines: predictedLines,
            edgeTrailPoints: guide.predictedEdges.points.compactMap(trailPoint))
    }

    /// The predicted edges as segments in guide fields: the top and bottom lines over the x
    /// range, and the right edge between them.
    static func predictedSegments(
        _ edges: PredictedEdges
    ) -> [(kind: PredictedTrailLine.Kind, from: CGPoint, to: CGPoint)] {
        guard let range = edges.xRange else { return [] }
        var segments: [(kind: PredictedTrailLine.Kind, from: CGPoint, to: CGPoint)] = []
        for (kind, fit) in [(PredictedTrailLine.Kind.top, edges.top), (.bottom, edges.bottom)] {
            guard let fit else { continue }
            segments.append(
                (
                    kind, CGPoint(x: range.lowerBound, y: fit.along(at: range.lowerBound)),
                    CGPoint(x: range.upperBound, y: fit.along(at: range.upperBound))
                ))
        }
        if let top = edges.top, let bottom = edges.bottom {
            for (kind, x) in [(PredictedTrailLine.Kind.left, edges.leftX), (.right, edges.rightX)] {
                guard let x else { continue }
                segments.append(
                    (kind, CGPoint(x: x, y: top.along(at: x)), CGPoint(x: x, y: bottom.along(at: x))))
            }
        }
        return segments
    }

    /// Within this of the cross, a speed above the touch limit shows "Ease off at the cross".
    /// PLACEHOLDER: 0.5 field, half the spot spacing's reach.
    private static let easeOffFields = 0.5
    private let briefThresholds = BriefTouchThresholds()

    private var spotModeName: String { spotMode == .briefTouch ? "brief_touch" : "hold_still" }

    /// End the run now, or when the current column finishes; or take that back. The next
    /// update shows the answer.
    func endNow() {
        guide.endNow()
        refreshEnding()
    }
    func endAfterColumn() {
        guide.endAfterColumn()
        refreshEnding()
    }
    func cancelEnd() {
        guide.cancelEndAfterColumn()
        refreshEnding()
    }

    private func refreshEnding() {
        isFinished = guide.isFinished
        finishReason = guide.finishReason
        pendingEnd = guide.pendingEnd
        countingActive = guide.countingActive
    }

    private static func isWrongWay(_ instruction: GuideInstruction?) -> Bool {
        switch instruction {
        case .tooFar?, .otherWay?: true
        default: false
        }
    }

    /// The helper's answer about an edge; the route changes at once (the next update shows it).
    func userEdge(_ feedback: EdgeFeedback, seconds: Double) {
        guard var reading = lastReading else { return }
        reading.seconds = seconds
        _ = guide.userEdge(feedback, reading)
        lastEdgeHeading = guide.edgeHeading
    }

    /// What the edge question is about now, captured when it is raised.
    var edgeQuestionSnapshot: EdgeQuestionSnapshot? { guide.edgeQuestionSnapshot }

    /// The helper's answer to an earlier question; false when it no longer applies.
    func answerEdgeQuestion(
        _ snapshot: EdgeQuestionSnapshot, _ feedback: EdgeFeedback, seconds: Double
    ) -> Bool {
        guard var reading = lastReading else { return false }
        reading.seconds = seconds
        let applied = guide.answerEdgeQuestion(snapshot, feedback, reading) != nil
        lastEdgeHeading = guide.edgeHeading
        return applied
    }

    func reset() {
        sideInsetApplied = false
        classifier.reset()
        var thresholds = GuidedSweepThresholds()
        thresholds.fullCoverSlip = fullCoverSlip
        thresholds.asksEdges = asksEdges
        thresholds.squareCoverSlip = coverSlip == .square
        thresholds.alignment.spotMode = spotMode
        thresholds.columnSpacingFields = coverageStep
        guide = GuidedSweep(thresholds: thresholds)
        isFinished = false
        finishReason = nil
        countingActive = false
        column = 0
        pendingEnd = false
        columnInProgress = false
        missedSpots = 0
        spotsTicked = 0
        edgeSpanFields = nil
        lastEdgeHeading = nil
        lastReading = nil
        lineState = ""
        captureCount = 0
        edgeCount = 0
        wrongWayCount = 0
        nudgeCount = 0
        rightEdgeSource = ""
        edgeReachedCount = 0
        lastHeading = nil
        lastInstruction = nil
        movingInstructionSince = nil
        stageLimitPressed = false
        stageLimitCount = 0
    }
}
