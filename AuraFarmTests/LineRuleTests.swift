import XCTest

@testable import AuraFarm

/// Phase 2p parts B and C: the line rule looks only along the leg, ignores edges it has met,
/// wants the empty side beyond the line and 2 s at rest, and (in the lab) waits for the helper.
final class LineRuleTests: XCTestCase {
    private let left = CGPoint(x: -0.1, y: 0)
    private let right = CGPoint(x: 0.1, y: 0)
    private let up = CGPoint(x: 0, y: -0.1)

    private func line(
        _ offset: Double, residual: Double? = 0.05, angle: Double = 0, before: Double? = nil,
        beyond: Double? = nil
    ) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: angle, offsetFields: offset,
            sign: 1, slideResidualFields: residual, path: [], isCandidate: true,
            beforeEnergy: before, beyondEnergy: beyond)
    }

    private func approach(
        _ route: ScriptedRoute, from start: Double, to end: Double, move: CGPoint,
        residual: Double? = 0.05
    ) {
        var offset = start
        while offset >= end - 1e-9 {
            route.feed(ScriptedRoute.Frame(line: line(offset, residual: residual)), move: move)
            offset -= 0.1
        }
    }

    private func rest(_ route: ScriptedRoute, _ offset: Double, readings: Int) {
        route.feed(
            ScriptedRoute.Frame(still: true, line: line(offset, residual: nil)), times: readings)
    }

    /// The left-edge line is found, rested on for 2.4 s and confirmed.
    private func leftEdge(_ route: ScriptedRoute) {
        route.feed(move: left, times: 10)
        approach(route, from: 1.0, to: 0.1, move: left)
        rest(route, 0.1, readings: 24)
    }

    // MARK: B1 the direction

    func testTheEdgeHeadingIsLeftOnTheRunNilOnTheInsetTripAndAlongTheLegOnColumnOne() {
        let route = ScriptedRoute(fullCoverSlip: true)
        route.feed(move: left, times: 10)
        XCTAssertEqual(route.guide.edgeHeading, CGPoint(x: -1, y: 0))
        approach(route, from: 1.0, to: 0.1, move: left)
        rest(route, 0.1, readings: 24)
        XCTAssertEqual(route.last.stateName, "column 1 up")
        XCTAssertNil(route.guide.edgeHeading, "the inset trip: the view is not on the column yet")
        route.feed(move: right, times: 6)
        XCTAssertEqual(
            route.guide.edgeHeading, CGPoint(x: 0, y: -1), "holding on the first spot: the leg")
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        XCTAssertEqual(route.guide.edgeHeading, CGPoint(x: 0, y: -1), "along the up leg")
    }

    func testTheRunOf1532TheSameLeftLineAtTheCrossOnTheInsetTripConfirmsNothing() {
        let route = ScriptedRoute(fullCoverSlip: true)
        leftEdge(route)
        XCTAssertEqual(route.guide.edgesReached, 1)
        // Heading screen-right to the column start, the probe saw the same line at the cross.
        for _ in 0..<6 {
            route.feed(ScriptedRoute.Frame(line: line(0.0, residual: 0.05)), move: right)
        }
        route.feed(ScriptedRoute.Frame(still: true, line: line(0.0, residual: nil)), times: 40)
        XCTAssertEqual(route.guide.edgesReached, 1, "no second confirmation")
        XCTAssertTrue(route.last.stateName.hasPrefix("column 1 up"), route.last.stateName)
        XCTAssertFalse(route.steps.suffix(46).contains { $0.edge.lineState == "attached" })
    }

    func testALineMeasuredAlongAnotherHeadingIsIgnored() {
        let route = ScriptedRoute(fullCoverSlip: true)
        route.feed(move: left, times: 10)
        var frame = ScriptedRoute.Frame(line: line(0.6))
        frame.lineHeading = CGPoint(x: 1, y: 0)  // measured along screen right, not left
        route.feed(frame, move: left, times: 8)
        XCTAssertEqual(route.last.edge.lineState, "none")
    }

    // MARK: B2 known and rejected edges

    func testAKnownEdgeLookedBackAtIsIgnoredAndANewParallelLineOneFieldOnIsNot() {
        var memory = LineEdgeMemory()
        let thresholds = LineEdgeThresholds()
        // The top edge, found heading up from (0, 5) with the line 0.1 ahead.
        memory.recordKnown(
            LineEdgeMemory.entry(
                normal: CGPoint(x: 0, y: -1), position: CGPoint(x: 0, y: 5), offsetFields: 0.1,
                angleDegrees: 0))
        func ignored(_ normal: CGPoint, y: Double, offset: Double) -> Bool {
            memory.ignores(
                normal: normal, position: CGPoint(x: 0, y: y), offsetFields: offset, angleDegrees: 0,
                thresholds: thresholds)
        }
        XCTAssertTrue(ignored(CGPoint(x: 0, y: 1), y: 5, offset: -0.1), "looking back at it")
        XCTAssertTrue(ignored(CGPoint(x: 0, y: 1), y: 4.8, offset: 0.1), "within 0.5 field")
        XCTAssertFalse(ignored(CGPoint(x: 0, y: 1), y: 3, offset: 0.9), "1.0 field further on")
        XCTAssertFalse(ignored(CGPoint(x: 0, y: -1), y: 5, offset: 0.1), "the next column's own approach")
        XCTAssertFalse(
            memory.ignores(
                normal: CGPoint(x: 0, y: 1), position: CGPoint(x: 0, y: 5), offsetFields: -0.1,
                angleDegrees: 40, thresholds: thresholds), "not within 15 degrees")
    }

    func testARejectedLineIsIgnoredWhicheverWayItIsApproachedUntilTheLegEnds() {
        var memory = LineEdgeMemory()
        memory.recordRejected(
            LineEdgeMemory.entry(
                normal: CGPoint(x: 0, y: -1), position: CGPoint(x: 0, y: 3), offsetFields: 0.1,
                angleDegrees: 0))
        let thresholds = LineEdgeThresholds()
        XCTAssertTrue(
            memory.ignores(
                normal: CGPoint(x: 0, y: -1), position: CGPoint(x: 0, y: 3), offsetFields: 0.1,
                angleDegrees: 0, thresholds: thresholds))
        memory.clearRejected()
        XCTAssertFalse(
            memory.ignores(
                normal: CGPoint(x: 0, y: -1), position: CGPoint(x: 0, y: 3), offsetFields: 0.1,
                angleDegrees: 0, thresholds: thresholds))
    }

    // MARK: B4 beyond-side evidence, B5 two seconds

    private func reading(
        _ seconds: Double, still: Double?, line: EdgeLine?, moving: Bool = false
    ) -> GuideReading {
        GuideReading(
            seconds: seconds, position: .zero, tracking: .tracking, unconfirmedGaps: 0,
            viewClass: .sample, speedFraction: 0.05, isStill: !moving, stillSeconds: still,
            edgeLine: line)
    }

    private func attachedTracker(before: Double?, beyond: Double?) -> LineEdgeTracker {
        var tracker = LineEdgeTracker(confirmSeconds: 2.0)
        for index in 0..<6 {
            tracker.update(
                reading(
                    Double(index) * 0.1, still: nil,
                    line: line(0.1, before: before, beyond: beyond), moving: true))
        }
        return tracker
    }

    func testALineWithMuchBeyondItIsRejectedAndOneWithLittleIsAccepted() {
        XCTAssertEqual(attachedTracker(before: 500, beyond: 300).state, .none, "300 against 500")
        XCTAssertEqual(attachedTracker(before: 500, beyond: 150).state, .none, "0.3 of before")
        XCTAssertEqual(attachedTracker(before: 500, beyond: 20).state, .attached, "20 against 500")
        XCTAssertEqual(attachedTracker(before: 500, beyond: 125).state, .attached, "exactly 0.25")
    }

    func testConfirmationNeedsTwoSecondsStillInARowAndNotOneNineSeconds() {
        var tracker = attachedTracker(before: 500, beyond: 20)
        XCTAssertEqual(tracker.state, .attached)
        var state = LineEdgeState.attached
        for index in 1...19 {  // 1.9 s at rest
            let resting = line(0.1, residual: nil, before: 500, beyond: 20)
            state = tracker.update(
                reading(1 + Double(index) * 0.1, still: Double(index) * 0.1, line: resting))
        }
        XCTAssertEqual(state, .attached, "1.9 s is not enough")
        state = tracker.update(
            reading(3.0, still: 2.0, line: line(0.1, residual: nil, before: 500, beyond: 20)))
        XCTAssertEqual(state, .confirmed)
        XCTAssertEqual(EdgeConfirmationThresholds().confirmSeconds, 2.0)
    }

    func testAskModeNeverConfirmsAloneAndAutoModeDoesWithAnAutoReason() {
        for asks in [true, false] {
            let route = ScriptedRoute(fullCoverSlip: true, asksEdges: asks)
            route.feed(move: left, times: 10)
            approach(route, from: 1.0, to: 0.1, move: left)
            rest(route, 0.1, readings: 40)
            if asks {
                XCTAssertEqual(route.guide.edgesReached, 0, "waits for a tap")
                XCTAssertEqual(route.last.instruction, .edgeDetected)
                XCTAssertTrue(route.last.edge.lineAtCross)
            } else {
                XCTAssertEqual(route.guide.edgesReached, 1)
                XCTAssertTrue(route.steps.contains { $0.edge.feedback == "auto" })
            }
        }
    }

    // MARK: C the helper's buttons

    func testYesConfirmsTheLineAtTheCrossAndEndsTheRun() {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        approach(route, from: 1.0, to: 0.1, move: left)
        rest(route, 0.1, readings: 5)
        XCTAssertTrue(route.last.edge.lineAtCross)
        let step = route.answer(.yes, ScriptedRoute.Frame(still: true, line: line(0.1, residual: nil)))
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(step.stateName, "column 1 up")
    }

    func testNoRejectsTheLineSaysKeepGoingForTwoSecondsAndDoesNotAskAgain() {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        approach(route, from: 1.0, to: 0.1, move: left)
        rest(route, 0.1, readings: 5)
        let step = route.answer(.no, ScriptedRoute.Frame(still: true, line: line(0.1, residual: nil)))
        XCTAssertEqual(step.instruction, .notAnEdge)
        XCTAssertEqual(route.guide.edgesReached, 0)
        // The same line a moment later, the view not having moved: it is ignored, and for 2 s the
        // words say "Not an edge. Keep going".
        let same = ScriptedRoute.Frame(still: true, line: line(0.1, residual: nil))
        route.feed(same, times: 10)
        XCTAssertEqual(route.last.stateName, "find left edge")
        XCTAssertEqual(route.last.edge.lineState, "none")
        XCTAssertTrue(route.instructions.suffix(10).allSatisfy { $0 == .notAnEdge })
        route.feed(same, times: 15)
        XCTAssertNotEqual(route.last.instruction, .notAnEdge, "after 2 s it is gone")
        XCTAssertEqual(route.last.instruction, .travel(direction: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(route.guide.edgesReached, 0)
    }

    func testMarkEdgeHereConfirmsAnEdgeTheRuleMissedAtTheCross() {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        XCTAssertTrue(route.last.edge.canMarkEdge)
        let step = route.answer(.mark)
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(step.stateName, "column 1 up")
        XCTAssertEqual(EdgeFeedback.mark.csvName, "mark")
        XCTAssertEqual(EdgeFeedback.yes.csvName, "yes")
        XCTAssertEqual(EdgeFeedback.no.csvName, "no")
    }

    func testAnEdgeCanBeMarkedWhileTheGuideSaysTurnBackTowardTheCross() {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: false)
        leftEdge(route)
        route.feed(move: right, times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        XCTAssertEqual(route.last.stateName, "column 1 up")
        // Drifted 0.5 field sideways: the guide says to turn back toward the cross; the line is
        // still looked for along the leg.
        route.feed(move: CGPoint(x: 0.1, y: 0), times: 5)
        XCTAssertEqual(route.guide.edgeHeading, CGPoint(x: 0, y: -1))
        XCTAssertTrue(route.last.edge.canMarkEdge, "the button is still there")
        let before = route.guide.edgesReached
        let step = route.answer(.mark)
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, before + 1)
        XCTAssertFalse(step.stateName.hasPrefix("column 1 up"), "the leg ended: \(step.stateName)")
    }

    func testAnAnswerThatDoesNotApplyChangesNothing() {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        route.feed(move: left, times: 10)
        let before = route.guide.edgesReached
        route.answer(.yes)  // no line at the cross
        route.answer(.no)  // no line at all
        XCTAssertEqual(route.guide.edgesReached, before)
        XCTAssertEqual(route.last.stateName, "find left edge")
        // Legacy mode ignores the buttons too.
        let legacy = ScriptedRoute()
        legacy.feed(move: left, times: 10)
        legacy.answer(.mark)
        XCTAssertEqual(legacy.guide.edgesReached, 0)
    }

    // MARK: Phase 2q parts B and D

    /// Column 1 is under way and the view has gone past the first spot: the guide says too far.
    private func columnOnePastTheTarget() -> ScriptedRoute {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true)
        leftEdge(route)
        route.feed(move: right, times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        route.feed(move: up, times: 12)
        return route
    }

    func testTheLineIsLookedForWhileTheGuideSaysTooFarAndCanReachTheConfirmStage() {
        let route = columnOnePastTheTarget()
        XCTAssertNotNil(route.guide.edgeHeading, "whatever the instruction")
        let before = route.guide.edgesReached
        approach(route, from: 1.0, to: 0.1, move: up, residual: 0.05)
        rest(route, 0.1, readings: 24)
        XCTAssertEqual(route.last.edge.lineState, "attached")
        XCTAssertTrue(route.last.edge.lineAtCross, "the stage where the helper is asked")
        XCTAssertEqual(route.guide.edgesReached, before, "asked, not confirmed alone")
    }

    func testALineWhileTheTrackerHasNothingToFollowIsAttachedFromTheChain() {
        // The tracker is paused (no detail): the residual comes from the frame shifts.
        let route = columnOnePastTheTarget()
        var offset = 1.0
        while offset >= 0.1 - 1e-9 {
            var frame = ScriptedRoute.Frame(tracking: .paused, line: line(offset, residual: 0.05))
            frame.line?.attachSource = "chain"
            route.feed(frame, move: up)
            offset -= 0.1
        }
        route.feed(
            ScriptedRoute.Frame(tracking: .paused, still: true, line: line(0.1, residual: nil)),
            times: 24)
        XCTAssertEqual(route.last.edge.lineState, "attached")
        XCTAssertTrue(route.last.edge.lineAtCross)
    }

    func testALineFixedOnScreenWhileTheFrameShiftsShowMovementIsNeverAttached() {
        let route = columnOnePastTheTarget()
        for _ in 0..<12 {
            var frame = ScriptedRoute.Frame(tracking: .paused, line: line(0.1, residual: 0.1 + 0.3))
            frame.line?.attachSource = "chain"
            route.feed(frame, move: up)
        }
        route.feed(
            ScriptedRoute.Frame(tracking: .paused, still: true, line: line(0.1, residual: nil)),
            times: 24)
        XCTAssertNotEqual(route.last.edge.lineState, "attached")
        XCTAssertNotEqual(route.last.edge.lineState, "confirmed")
    }

    func testTheLineAttachSourceIsFollowedOnlyByTheSpotAndCountingColumns() {
        // 32 columns (spot check, coverage, counting, event detail, model, units, camera, phone, edge
        // acceptance, camera drops and the guided scan's knob words) follow it.
        XCTAssertEqual(MovementLog.header[MovementLog.header.count - 41], "line_attach_source")
    }
}
