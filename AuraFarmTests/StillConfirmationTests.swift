import XCTest

@testable import AuraFarm

/// Phase 2o part A: an edge is confirmed only while the helper has been still, a second in a row.
/// Detecting and showing a candidate while moving is fine; confirming is not.
final class StillConfirmationTests: XCTestCase {
    private let route = ScriptedRoute()

    private func isChecking(_ instruction: GuideInstruction) -> Double? {
        if case .checkingEdge(let progress) = instruction { return progress }
        return nil
    }

    func testAHalfEdgeWhileMovingSlowlyIsNeverConfirmedAndThenTwoSecondsStillConfirms() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 3)
        let edgesBefore = route.guide.edgesReached
        // 3 s of alternating still and moving frames.
        for _ in 0..<15 {
            route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: true))
            route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: false))
        }
        XCTAssertEqual(route.guide.edgesReached, edgesBefore, "never confirmed while moving")
        XCTAssertTrue(route.last.stateName.hasPrefix("column 1 up"))
        route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: true), times: 24)
        XCTAssertEqual(route.guide.edgesReached, edgesBefore + 1, "confirmed after 2 s at rest")
    }

    func testTheWholeBoxGoingBlankWhileMovingIsNotConfirmedUntilTwoSecondsStill() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 8)
        route.feed(.blank, move: ScriptedRoute.up, times: 4)
        route.feed(.blank, times: 30)  // 3 s, the helper still moving (not still)
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        XCTAssertFalse(
            route.instructions.contains { if case .edgeGoBack = $0 { true } else { false } })
        route.feed(.blankStill, times: 24)
        XCTAssertEqual(route.guide.edgesGoneBack, 1)
    }

    func testAStillFlickerResetsTheProgress() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 3)
        let edge = ScriptedRoute.Frame(ahead: 50, behind: 250, still: true)
        route.feed(edge, times: 7)
        let before = isChecking(route.last.instruction) ?? -1
        XCTAssertGreaterThan(before, 0.3, "building up")
        route.feed(ScriptedRoute.Frame(ahead: 50, behind: 250, still: false))
        XCTAssertEqual(isChecking(route.last.instruction), 0, "a moving reading starts it again")
        XCTAssertEqual(route.last.edge.reason, "moving")
        route.feed(edge, times: 7)
        let after = isChecking(route.last.instruction) ?? 1
        XCTAssertLessThan(after, 0.8, "not the progress it had, and not confirmed")
        XCTAssertEqual(route.guide.edgesReached, 1)
    }

    func testTheStillnessThatConfirmsIsTheSlidesOwnSecondInARow() {
        // The candidate holds 1 s, but the slide has only been still for 0.4 s: not yet.
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 3)
        let edge = ScriptedRoute.Frame(ahead: 50, behind: 250, still: true)
        route.feed(edge, times: 3)
        var reading = route.reading(edge)
        reading.stillSeconds = 0.4
        XCTAssertFalse(reading.isStill(for: 1.0))
        reading.stillSeconds = 1.0
        XCTAssertTrue(reading.isStill(for: 1.0))
        reading.stillSeconds = nil
        XCTAssertEqual(reading.isStill(for: 1.0), reading.isStill, "unknown: isStill decides")
    }
}
