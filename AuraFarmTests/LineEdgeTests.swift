import XCTest

@testable import AuraFarm

/// Phase 2o part B: in full-cover-slip mode the edge is the cover slip's line, and only a line
/// proven to move with the slide, at the centre cross, at rest for a second, is confirmed.
final class LineEdgeTests: XCTestCase {
    private let route = ScriptedRoute(fullCoverSlip: true)
    private let left = CGPoint(x: -0.1, y: 0)
    private let right = CGPoint(x: 0.1, y: 0)
    private let up = CGPoint(x: 0, y: -0.1)

    private func line(
        _ offset: Double, residual: Double? = 0.05, angle: Double = 0, candidate: Bool = true
    ) -> EdgeLine {
        EdgeLine(
            strength: 12, coverage: 1, longestRun: 8, angleDegrees: angle, offsetFields: offset,
            sign: 1, slideResidualFields: residual, path: [], isCandidate: candidate)
    }

    private func moving(
        _ offset: Double, residual: Double? = 0.05, angle: Double = 0, move: CGPoint
    ) {
        route.feed(
            ScriptedRoute.Frame(line: line(offset, residual: residual, angle: angle)), move: move)
    }

    /// The line comes from `from` fields ahead to `to`, the helper moving `move` a reading.
    private func approach(
        from start: Double, to end: Double, move: CGPoint, residual: Double? = 0.05,
        angle: Double = 0
    ) {
        var offset = start
        while offset >= end - 1e-9 {
            moving(offset, residual: residual, angle: angle, move: move)
            offset -= 0.1
        }
    }

    private func rest(_ offset: Double, readings: Int, angle: Double = 0) {
        route.feed(
            ScriptedRoute.Frame(still: true, line: line(offset, residual: nil, angle: angle)),
            times: readings)
    }

    /// Travels left onto sample, the left edge line arrives and is confirmed, and the first spot
    /// of column 1 is taken.
    private func columnOne() {
        route.feed(move: left, times: 10)
        approach(from: 1.0, to: 0.1, move: left)
        rest(0.1, readings: 24)
        route.feed(move: right, times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
    }

    func testTheLeftEdgeLineStartsColumnOneInsideIt() {
        columnOne()
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertTrue(route.instructions.contains(.edgeReached))
        XCTAssertEqual(route.guide.placements.count, 1)
        XCTAssertEqual(route.last.stateName, "column 1 up")
        XCTAssertEqual(route.last.edge.edgeMode, "line")
    }

    func testASparsePatchWithNoLineIsNoEdgeAndTheColumnCarriesOn() {
        columnOne()
        route.feed(move: up, times: 3)
        // The half ahead sparse, then the whole box blank: both only logged.
        route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: true), times: 30)
        route.feed(.blankStill, times: 40)
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        XCTAssertEqual(route.last.stateName, "column 1 up")
        XCTAssertFalse(route.instructions.contains { if case .edgeGoBack = $0 { true } else { false } })
        XCTAssertTrue(route.steps.contains { $0.edge.candidate == "half_edge" }, "still logged")
    }

    func testALineApproachingAttachedAndRestedOnIsConfirmedAndTheLegEnds() {
        columnOne()
        approach(from: 1.5, to: 0.1, move: up)
        XCTAssertTrue(route.instructions.contains(.lineAhead))
        XCTAssertTrue(route.steps.contains { $0.edge.lineState == "attached" })
        XCTAssertEqual(route.guide.edgesReached, 1, "not yet: it is still moving")
        rest(0.1, readings: 24)
        XCTAssertEqual(route.guide.edgesReached, 2)
        XCTAssertTrue(route.steps.contains { $0.edge.reason == "line_attached" })
        XCTAssertTrue(route.steps.contains { $0.edge.reason == "line_confirmed" })
        XCTAssertFalse(
            route.last.stateName.hasPrefix("column 1 up"), "the leg ended: \(route.last.stateName)")
    }

    func testTheLineAtTheCrossWhileStillMovingIsNotConfirmedUntilOneSecondStill() {
        columnOne()
        approach(from: 1.5, to: 0.1, move: up)
        for _ in 0..<30 { moving(0.1, move: CGPoint(x: 0, y: -0.01)) }  // 3 s of creeping
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertTrue(route.last.stateName.hasPrefix("column 1 up"))
        rest(0.1, readings: 24)
        XCTAssertEqual(route.guide.edgesReached, 2)
    }

    func testALineFixedToTheOpticsIsNeverAttachedAndNeverConfirmed() {
        columnOne()
        // The slide moves 0.1 a reading while the line stays put: residual about the movement.
        let first = route.steps.count
        approach(from: 1.5, to: 0.1, move: up, residual: 0.3)
        rest(0.1, readings: 30)
        XCTAssertFalse(route.steps[first...].contains { $0.edge.lineState == "attached" })
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertTrue(route.last.stateName.hasPrefix("column 1 up"))
        // At the cross, still, never seen to move with the slide: step back to prove it.
        guard case .checkEdge = route.last.instruction else {
            return XCTFail("expected checkEdge, got \(route.last.instruction)")
        }
    }

    func testALineSixtyDegreesFromPerpendicularIsIgnored() {
        columnOne()
        let first = route.steps.count
        approach(from: 1.5, to: 0.1, move: up, angle: 60)
        rest(0.1, readings: 30, angle: 60)
        XCTAssertEqual(route.last.edge.lineState, "none")
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertFalse(route.steps[first...].contains { $0.instruction == .lineAhead })
    }

    func testInLineModeABlankBoxSaysNothingToFollowAndNeverCheckEdgeOrAnEdge() {
        columnOne()
        route.feed(move: up, times: 3)
        route.feed(ScriptedRoute.Frame.blank, times: 6)
        route.feed(.blankStill, times: 40)
        XCTAssertTrue(route.instructions.contains(.nothingToFollow))
        XCTAssertFalse(
            route.instructions.contains { if case .checkEdge = $0 { true } else { false } })
        XCTAssertFalse(route.instructions.contains { if case .checkingEdge = $0 { true } else { false } })
        XCTAssertEqual(route.guide.edgesReached, 1)
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        XCTAssertEqual(route.last.edge.verdict, "off", "logged, but off in line mode")
        XCTAssertEqual(
            GuideInstruction.nothingToFollow.helperText,
            "Nothing to follow here. Turn back, or move to a patch with more particles")
        // The step-back words for a line at the cross that was never seen to move with the slide.
        XCTAssertEqual(
            GuideInstruction.checkEdge(toward: .zero).helperText(fullCoverSlip: true),
            "Step back until the edge line is in view")
    }

    func testALineBehindTheCrossOrGoneForHalfASecondResetsTheState() {
        columnOne()
        approach(from: 1.0, to: 0.9, move: up)  // two readings: seen, not yet attached
        XCTAssertEqual(route.last.edge.lineState, "ahead")
        route.feed(move: up, times: 8)  // no line for 0.8 s
        XCTAssertEqual(route.last.edge.lineState, "none")
    }

    func testTheToggleOffIsTheLegacyRuleAndSaysSo() {
        let legacy = ScriptedRoute()
        legacy.startColumnOne()
        legacy.feed(move: up, times: 3)
        legacy.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: true), times: 24)
        XCTAssertEqual(legacy.guide.edgesReached, 2, "a half edge still ends the leg")
        XCTAssertEqual(legacy.last.edge.edgeMode, "legacy")
        XCTAssertEqual(legacy.last.edge.lineState, "")
    }

    func testFinishReasonRightEdgeEncodesAndOldValuesStillDecode() throws {
        let decoder = JSONDecoder()
        for old in ["sampleFinished", "endedByHelper", "storageFull", "stageLimit"] {
            XCTAssertNotNil(try decoder.decode(SweepFinishReason?.self, from: Data("\"\(old)\"".utf8)))
        }
        XCTAssertEqual(SweepFinishReason.rightEdge.rawValue, "rightEdge")
        let encoded = try JSONEncoder().encode(SweepFinishReason.rightEdge)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"rightEdge\"")
        XCTAssertEqual(try decoder.decode(SweepFinishReason.self, from: encoded), .rightEdge)
    }
}
