import CoreGraphics
import XCTest

@testable import AuraFarm

/// The back-and-forth loop at an edge that does not confirm (20 Nov 2026 report): a line passed
/// again and again without attaching asks the helper, and going back aims at the line.
final class RepeatLineTests: XCTestCase {
    private let up = CGPoint(x: 0, y: -0.1)
    private let down = CGPoint(x: 0, y: 0.1)
    /// The slide's y of the edge line on column 1's up leg.
    private let lineY = -2.0

    /// A line at the slide's `lineY`, seen from `y` on an up leg (heading (0, -1)), never attached.
    private func line(from y: Double, lineY: Double? = nil) -> EdgeLine {
        EdgeLine(
            strength: 11, coverage: 1, longestRun: 8, angleDegrees: 0,
            offsetFields: y - (lineY ?? self.lineY), sign: 1, slideResidualFields: nil, path: [],
            isCandidate: true, beforeEnergy: 10, beyondEnergy: 0.9)
    }

    /// Column 1, on its up leg, 0.8 field up from where the leg began.
    private func columnOne(asksEdges: Bool = true) -> ScriptedRoute {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: asksEdges)
        let left = CGPoint(x: -0.1, y: 0)
        route.feed(move: left, times: 10)
        var offset = 1.0
        while offset >= 0.1 - 1e-9 {
            route.feed(ScriptedRoute.Frame(line: Self.leftLine(offset)), move: left)
            offset -= 0.1
        }
        route.feed(ScriptedRoute.Frame(still: true, line: Self.leftLine(0.1)), times: 24)
        if asksEdges { route.answer(.yes) }
        route.feed(move: CGPoint(x: 0.1, y: 0), times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        route.feed(move: up, times: 8)
        return route
    }

    private static func leftLine(_ offset: Double) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: offset,
            sign: 1, slideResidualFields: offset > 0.15 ? 0.05 : nil, path: [], isCandidate: true,
            beforeEnergy: nil, beyondEnergy: nil)
    }

    /// Moves along the leg to `y` in 0.1 steps, the line in view all the way.
    private func go(_ route: ScriptedRoute, to y: Double, lineY: Double? = nil) {
        while abs(Double(route.position.y) - y) > 0.05 {
            let dy = y < Double(route.position.y) ? -0.1 : 0.1
            let next = Double(route.position.y) + dy
            route.feed(ScriptedRoute.Frame(line: line(from: next, lineY: lineY)), move: CGPoint(x: 0, y: dy))
        }
    }

    /// Passes the line going up, then comes back to just before it.
    private func passAndReturn(_ route: ScriptedRoute) {
        go(route, to: lineY - 0.5)
        go(route, to: lineY + 0.2)
    }

    func testTheSecondPassRaisesTheQuestionAndTheGuideStopsSendingTheHelperForward() throws {
        let route = columnOne()
        go(route, to: lineY - 0.5)
        XCTAssertEqual(route.last.edge.lineCrossings, 1)
        XCTAssertFalse(route.last.edge.expectedEdgeAsk, "once is not a loop")
        go(route, to: lineY + 0.2)
        XCTAssertFalse(route.last.edge.expectedEdgeAsk)
        go(route, to: lineY - 0.5)
        XCTAssertEqual(route.last.edge.lineCrossings, 2)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        XCTAssertEqual(route.steps.filter { $0.edge.reason == "edge_question_repeat" }.count, 1)
        XCTAssertEqual(try XCTUnwrap(route.last.edge.lineAlong), -lineY, accuracy: 0.05)
        // Hold still, the cross on the line: no more "a little further" or "come back".
        go(route, to: lineY - 0.8)
        XCTAssertEqual(route.last.instruction, .edgeDetected)
        XCTAssertEqual(try XCTUnwrap(route.last.target?.y), lineY, accuracy: 0.05)
        guard case .line(let point, _)? = route.guide.edgeQuestionSnapshot else {
            return XCTFail("the question is about the line")
        }
        XCTAssertEqual(Double(point.y), lineY, accuracy: 0.05)
    }

    func testYesConfirmsTheEdgeAtTheLinesSlidePositionAndTheLegEnds() throws {
        let route = columnOne()
        passAndReturn(route)
        go(route, to: lineY - 0.5)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        let edges = route.guide.edgesReached
        let step = route.answer(.yes, ScriptedRoute.Frame(still: true))
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, edges + 1)
        let point = try XCTUnwrap(route.guide.predictedEdges.points.last)
        XCTAssertEqual(Double(point.y), lineY, accuracy: 0.05)
    }

    func testNoRejectsTheLineAndItDoesNotAskAgainOnThisLeg() {
        let route = columnOne()
        passAndReturn(route)
        go(route, to: lineY - 0.5)
        let edges = route.guide.edgesReached
        XCTAssertEqual(route.answer(.no, ScriptedRoute.Frame(still: true)).instruction, .notAnEdge)
        XCTAssertEqual(route.guide.edgesReached, edges)
        let answered = route.steps.count
        for _ in 0..<3 {
            passAndReturn(route)
            go(route, to: lineY - 0.5)
        }
        XCTAssertFalse(route.steps[answered...].contains { $0.edge.expectedEdgeAsk })
        XCTAssertNil(route.guide.edgeQuestionSnapshot)
        XCTAssertFalse(route.guide.isFinished)
    }

    func testALineMoreThanASameLineAwayStartsANewCount() {
        let route = columnOne()
        go(route, to: lineY - 0.5)
        XCTAssertEqual(route.last.edge.lineCrossings, 1)
        // The detector now reports a line 0.6 further on: another line.
        let other = lineY - 0.6
        go(route, to: other + 0.3, lineY: other)
        XCTAssertEqual(route.last.edge.lineCrossings, 0)
        go(route, to: other - 0.5, lineY: other)
        XCTAssertEqual(route.last.edge.lineCrossings, 1, "its own first pass")
        XCTAssertFalse(route.last.edge.expectedEdgeAsk)
    }

    func testGoingBackAimsAtTheLineAndHoldsWithinTheCrossBand() throws {
        let route = columnOne()
        go(route, to: lineY - 0.5)
        guard case .edgeBehind = route.last.instruction else { return XCTFail("behind") }
        XCTAssertEqual(try XCTUnwrap(route.last.target?.y), lineY, accuracy: 0.05)
        // Back to 0.2 from the line (inside the band): hold, not "a little further".
        go(route, to: lineY + 0.2)
        XCTAssertEqual(route.last.instruction, .edgeDetected)
        XCTAssertEqual(try XCTUnwrap(route.last.target?.y), lineY, accuracy: 0.05)
        // 0.4 ahead is outside the band: the ordinary lead words stay.
        go(route, to: lineY + 0.4)
        XCTAssertNotEqual(route.last.instruction, .edgeDetected)
    }

    func testARepeatedLineAsksWhateverAsksEdgesSays() {
        let route = columnOne(asksEdges: false)
        passAndReturn(route)
        go(route, to: lineY - 0.5)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        XCTAssertNotNil(route.guide.edgeQuestionSnapshot)
    }

    func testTheCsvColumnsAreAppendedAndTheBackWordsSayTheLine() {
        XCTAssertEqual(
            Array(MovementLog.header.suffix(2)), ["line_crossings", "line_along"])
        XCTAssertEqual(
            HelperInstruction.make(
                for: .edgeBehind(toward: CGPoint(x: 0, y: 1)), arrow: CGPoint(x: 0, y: 1),
                rule: KnobRule(), asksEdge: false)?.text.hasPrefix("Back to the line: "), true)
    }
}
