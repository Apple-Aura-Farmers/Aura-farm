import XCTest

@testable import AuraFarm

/// Phase 2h part E2: while paused the route is not fed, and resuming clears its timers.
final class GuidedSweepPauseTests: XCTestCase {
    private let route = ScriptedRoute()

    func testWhilePausedThereIsNoCaptureAndNoEdgeEvenWithEdgeLikeReadings() {
        route.startColumnOne()
        let captures = route.guide.placements.count
        let edges = route.guide.edgesReached
        route.guide.pause(.alignment)
        // On the next target and holding still: would be a capture.
        route.feed(move: ScriptedRoute.up, times: 8)
        route.feed(ScriptedRoute.Frame(still: true), times: 20)
        XCTAssertEqual(route.guide.placements.count, captures)
        // The half ahead over the edge, held still: would be an edge.
        route.feed(.edgeAhead, times: 30)
        route.feed(.blank, times: 30)
        XCTAssertEqual(route.guide.edgesReached, edges)
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        XCTAssertTrue(route.steps.suffix(80).allSatisfy { $0.instruction == .paused(.alignment) })
        XCTAssertTrue(route.steps.suffix(80).allSatisfy { $0.capture == nil })
        XCTAssertEqual(route.last.stateName, "paused")
    }

    func testAfterResumeAFreshLowDetailStretchIsNeededBeforeAnyEdge() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 3)
        // Blank for 0.5 s: the stretch is under way (the edge needs 0.8 s of it).
        route.feed(.blank, times: 5)
        route.guide.pause(.focus)
        route.feed(.blank, times: 100)
        XCTAssertEqual(route.last.instruction, .paused(.focus))
        route.guide.resume(seconds: route.seconds)
        XCTAssertEqual(route.guide.pauseReason, nil)
        // The 10 s of the gap do not count: 0.6 s of blank is not an edge.
        route.feed(.blank, times: 6)
        XCTAssertFalse(
            route.instructions.suffix(6).contains {
                if case .checkingEdge = $0 { true } else if case .edgeGoBack = $0 { true } else { false }
            })
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        // A fresh stretch of its own does decide, as it always did.
        route.feed(.blank, times: 30)
        XCTAssertEqual(route.guide.edgesGoneBack, 1)
    }

    func testPausingAFinishedRouteChangesNothing() {
        route.guide.finish(reason: .endedByHelper)
        route.guide.pause(.alignment)
        route.feed()
        XCTAssertEqual(route.last.instruction, .finished)
    }
}
