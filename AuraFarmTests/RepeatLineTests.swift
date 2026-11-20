import CoreGraphics
import XCTest

@testable import AuraFarm

/// The back-and-forth loop at an edge that does not confirm (20 Nov 2026 report): "edge just
/// behind" episodes at one place on the leg ask the helper, whether or not the line stayed
/// accepted in between; going back aims at the line.
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

    /// Moves along the leg to `y` in 0.1 steps, the line in view all the way (or never, with
    /// `showLine` false).
    private func go(
        _ route: ScriptedRoute, to y: Double, lineY: Double? = nil, showLine: Bool = true
    ) {
        while abs(Double(route.position.y) - y) > 0.05 {
            let dy = y < Double(route.position.y) ? -0.1 : 0.1
            let next = Double(route.position.y) + dy
            route.feed(
                ScriptedRoute.Frame(line: showLine ? line(from: next, lineY: lineY) : nil),
                move: CGPoint(x: 0, y: dy))
        }
    }

    /// One "edge just behind" episode at the line `at` (slide y): up past it with the line in
    /// view, then back down far below it with the line out of view (a dropout).
    private func episode(_ route: ScriptedRoute, at lineY: Double) {
        go(route, to: lineY - 0.4, lineY: lineY)
        guard case .edgeBehind = route.last.instruction else { return XCTFail("no episode") }
        go(route, to: -1.2, showLine: false)
    }

    private let first = -2.15  // slide position 2.15 along the leg
    private let second = -2.40  // 2.40: inside sameLineFields of the first

    func testTwoEpisodesWithTheLineDroppedBetweenRaiseTheQuestionOnTheSecond() throws {
        let route = columnOne()
        episode(route, at: first)
        XCTAssertEqual(route.last.edge.lineCrossings, 1)
        XCTAssertFalse(route.last.edge.expectedEdgeAsk, "once is not a loop")
        go(route, to: second - 0.4, lineY: second)
        XCTAssertEqual(route.last.edge.lineCrossings, 2)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        XCTAssertEqual(route.steps.filter { $0.edge.reason == "edge_question_repeat" }.count, 1)
        XCTAssertEqual(try XCTUnwrap(route.last.edge.lineAlong), -second, accuracy: 0.1)
        // Hold still, the cross on the line: no more "back to the line".
        go(route, to: second - 0.8, lineY: second)
        XCTAssertEqual(route.last.instruction, .edgeDetected)
        XCTAssertEqual(try XCTUnwrap(route.last.target?.y), second, accuracy: 0.1)
        guard case .line(let point, _)? = route.guide.edgeQuestionSnapshot else {
            return XCTFail("the question is about the line")
        }
        XCTAssertEqual(Double(point.y), second, accuracy: 0.1)
    }

    func testALineFarAwayInBetweenDoesNotResetTheCount() {
        let route = columnOne()
        episode(route, at: first)
        episode(route, at: -3.5)
        XCTAssertEqual(route.last.edge.lineCrossings, 1, "its own first episode")
        XCTAssertFalse(route.last.edge.expectedEdgeAsk)
        go(route, to: second - 0.4, lineY: second)
        XCTAssertEqual(route.last.edge.lineCrossings, 2)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
    }

    func testADropoutLongerThanTheLineMemoryDoesNotResetTheCount() {
        let route = columnOne()
        episode(route, at: first)
        route.feed(ScriptedRoute.Frame(still: true), times: 40)  // 4 s, memory is 2 s
        go(route, to: second - 0.4, lineY: second)
        XCTAssertEqual(route.last.edge.lineCrossings, 2)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
    }

    func testYesConfirmsTheEdgeAtTheLocationAndTheLegEndsClean() throws {
        let route = columnOne()
        episode(route, at: first)
        go(route, to: second - 0.4, lineY: second)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        let edges = route.guide.edgesReached
        let step = route.answer(.yes, ScriptedRoute.Frame(still: true))
        XCTAssertEqual(step.instruction, .edgeReached)
        XCTAssertEqual(route.guide.edgesReached, edges + 1)
        let point = try XCTUnwrap(route.guide.predictedEdges.points.last)
        XCTAssertEqual(Double(point.y), second, accuracy: 0.1)
        XCTAssertNil(route.guide.edgeQuestionSnapshot)
        route.feed(ScriptedRoute.Frame(still: true))
        XCTAssertEqual(route.last.edge.lineCrossings, 0, "the leg ended: the list is gone")
    }

    func testNoRejectsTheLocationAndItDoesNotAskAgainOnThisLeg() {
        let route = columnOne()
        episode(route, at: first)
        go(route, to: second - 0.4, lineY: second)
        let edges = route.guide.edgesReached
        XCTAssertEqual(route.answer(.no, ScriptedRoute.Frame(still: true)).instruction, .notAnEdge)
        XCTAssertEqual(route.guide.edgesReached, edges)
        let answered = route.steps.count
        go(route, to: -1.2, showLine: false)
        for _ in 0..<3 {
            go(route, to: first - 0.4, lineY: first)
            go(route, to: -1.2, showLine: false)
        }
        XCTAssertFalse(route.steps[answered...].contains { $0.edge.expectedEdgeAsk })
        XCTAssertNil(route.guide.edgeQuestionSnapshot)
        XCTAssertFalse(route.guide.isFinished)
    }

    func testANormalConfirmationStillWorksAndAsksNothing() {
        let route = columnOne(asksEdges: false)
        var offset = 1.0
        while offset >= 0.1 - 1e-9 {
            route.feed(ScriptedRoute.Frame(line: Self.leftLine(offset)), move: up)
            offset -= 0.1
        }
        route.feed(ScriptedRoute.Frame(still: true, line: Self.leftLine(0.1)), times: 24)
        XCTAssertTrue(route.instructions.contains(.edgeReached))
        XCTAssertFalse(route.steps.contains { $0.edge.reason == "edge_question_repeat" })
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

    func testARepeatedLocationAsksWhateverAsksEdgesSays() {
        let route = columnOne(asksEdges: false)
        episode(route, at: first)
        go(route, to: second - 0.4, lineY: second)
        XCTAssertTrue(route.last.edge.expectedEdgeAsk)
        XCTAssertNotNil(route.guide.edgeQuestionSnapshot)
    }

    // MARK: Spots stop short of a line the route can see

    /// Chases the current target 0.1 field a reading, holding still on it, `line` showing the
    /// line at slide y `lineY` (or nothing). Returns the captures' y positions.
    @discardableResult
    private func chase(
        _ route: ScriptedRoute, lineY: Double? = nil, readings: Int = 160
    ) -> [Double] {
        let before = route.guide.placements.count
        for _ in 0..<readings {
            guard let target = route.last.target else { break }
            let y = Double(route.position.y)
            let dy = Double(target.y) - y
            let moving = abs(dy) > 0.05
            let step = moving ? max(-0.1, min(0.1, dy)) : 0
            route.feed(
                ScriptedRoute.Frame(still: !moving, line: lineY.map { line(from: y + step, lineY: $0) }),
                move: CGPoint(x: 0, y: step))
        }
        return route.guide.placements.dropFirst(before).map { Double($0.position.y) }
    }

    func testNoSpotIsPlacedBeyondAnAcceptedLineLessTheMarginThenTheLegSeeksTheEdge() {
        let route = columnOne()
        // The line is at slide position 2.5 (y = -2.5); the margin is 0.6 without a known circle.
        let spots = chase(route, lineY: -2.5)
        XCTAssertFalse(spots.isEmpty)
        XCTAssertGreaterThanOrEqual(spots.min() ?? 0, -2.5 + 0.6 - 0.1, "\(spots)")
        XCTAssertEqual(route.last.edge.spotLimitReason, "line")
        XCTAssertFalse(route.guide.isFinished)
        // Seeking: more readings place nothing and the card says travel.
        let more = chase(route, lineY: -2.5, readings: 40)
        XCTAssertTrue(more.isEmpty, "\(more)")
    }

    func testAnEdgeLoopLocationCapsSpotsTheSameWay() {
        let route = columnOne()
        episode(route, at: first)  // 2.15 along, one episode: recorded, no question yet
        XCTAssertFalse(route.last.edge.expectedEdgeAsk)
        route.feed(ScriptedRoute.Frame(still: true), times: 30)  // the line is forgotten, the location is not
        let spots = chase(route)
        XCTAssertGreaterThanOrEqual(spots.min() ?? 0, first + 0.6 - 0.1, "\(spots)")
        XCTAssertEqual(route.last.edge.spotLimitReason, "loop_location")
    }

    // MARK: No spots into empty glass

    private func emptyFrame() -> ScriptedRoute.Frame {
        ScriptedRoute.Frame(
            aheadAway: 4, aheadToward: 4, behindAway: 50, behindToward: 50)  // 0.08 ahead over behind
    }

    func testAnEmptyAreaAheadForHalfASecondStopsSpotsButNeverConfirmsAnEdge() {
        let route = columnOne()
        let edges = route.guide.edgesReached
        route.feed(emptyFrame(), move: up, times: 7)
        XCTAssertEqual(route.last.edge.spotLimitReason, "empty_ahead")
        let placed = route.guide.placements.count
        route.feed(emptyFrame(), move: up, times: 30)
        XCTAssertEqual(route.guide.placements.count, placed, "no further spot")
        XCTAssertEqual(route.guide.edgesReached, edges, "empty alone confirms nothing")
        XCTAssertFalse(route.guide.isFinished)
    }

    func testABriefEmptyPatchDoesNotStopPlacement() {
        let route = columnOne()
        route.feed(emptyFrame(), move: up, times: 3)
        route.feed(move: up, times: 3)
        XCTAssertEqual(route.last.edge.spotLimitReason, "")
        route.feed(emptyFrame(), move: up, times: 3)
        XCTAssertEqual(route.last.edge.spotLimitReason, "")
        XCTAssertFalse(chase(route).isEmpty, "spots are still placed")
    }

    func testTheCsvColumnsAreAppendedAndTheBackWordsSayTheLine() {
        XCTAssertEqual(
            Array(MovementLog.header.suffix(4)),
            ["line_crossings", "line_along", "spot_limit_reason", "slip_tilt_deg"])
        XCTAssertEqual(
            HelperInstruction.make(
                for: .edgeBehind(toward: CGPoint(x: 0, y: 1)), arrow: CGPoint(x: 0, y: 1),
                rule: KnobRule(), asksEdge: false)?.text.hasPrefix("Back to the line: "), true)
    }
}
