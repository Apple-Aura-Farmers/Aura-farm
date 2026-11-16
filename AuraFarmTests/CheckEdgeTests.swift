import XCTest

@testable import AuraFarm

/// Phase 2h part F: a picture that goes blank under a helper who was moving normally is probably
/// an edge, so the guide says to step back and come forward again at once. A blank that began
/// while resting, or at a flick, stays "Refocus" (a flick or blur is not an edge).
final class CheckEdgeTests: XCTestCase {
    private let route = ScriptedRoute()

    /// The picture went soft under the helper (both halves blurred, same content): the verdict
    /// is blur, which is what Test 4's top edge looked like.
    private func blurred(still: Bool, speed: Double = 0.05) -> ScriptedRoute.Frame {
        ScriptedRoute.Frame(
            viewClass: .blurry, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
            behindFocus: nil, sideA: nil, sideB: nil, still: still, speed: speed)
    }

    private func isCheckEdge(_ instruction: GuideInstruction) -> Bool {
        if case .checkEdge = instruction { return true }
        return false
    }

    /// Up the column, then the box going soft: two tracked readings already blurred, then
    /// nothing to follow (the position freezes). What the helper was doing is read from the
    /// readings WITH detail before the onset, so those are what is set here; the onset readings'
    /// own speed (`onsetSpeed`) is noise on a blank frame and must not matter.
    /// - Parameters:
    ///   - beforeStill: the helper rests before the onset (a Z-knob blur) instead of moving.
    ///   - flickSpeed: one detail reading 0.2 s before the onset at this speed (a flick).
    private func goSoft(
        beforeStill: Bool = false, flickSpeed: Double? = nil, onsetSpeed: Double = 0.05
    ) {
        route.startColumnOne()
        if beforeStill {
            route.feed(ScriptedRoute.Frame(still: true), times: 4)
        } else if let flickSpeed {
            route.feed(move: ScriptedRoute.up, times: 2)
            route.feed(ScriptedRoute.Frame(speed: flickSpeed), move: ScriptedRoute.up)
            route.feed(move: ScriptedRoute.up)
        } else {
            route.feed(move: ScriptedRoute.up, times: 3)
        }
        let soft = ScriptedRoute.Frame(
            viewClass: .blurry, ahead: 60, behind: 60, aheadFocus: 0.3, behindFocus: 0.3,
            sideA: 60, sideB: 60, still: false, speed: onsetSpeed)
        route.feed(soft, times: 2)
        route.feed(blurred(still: false, speed: onsetSpeed), times: 14)
    }

    func testAMovingBeforeTheOnsetGivesCheckEdgeAtOnceWhateverTheOnsetSpeed() {
        goSoft(onsetSpeed: 0.6)
        XCTAssertTrue(route.instructions.contains(where: isCheckEdge))
        XCTAssertFalse(route.instructions.contains(.refocus))
        // Toward the last spot with sample: back down the column.
        if case .checkEdge(let toward) = route.last.instruction {
            XCTAssertGreaterThan(toward.y, 0)
        } else {
            XCTFail("expected checkEdge, got \(route.last.instruction)")
        }
        XCTAssertEqual(route.last.instruction.csvName, "check_edge")
        XCTAssertEqual(route.last.instruction.helperText, "Step back a little, then come forward again")
    }

    func testAStillBeforeTheOnsetGivesRefocus() {
        goSoft(beforeStill: true)
        XCTAssertTrue(route.instructions.contains(.refocus))
        XCTAssertFalse(route.instructions.contains(where: isCheckEdge))
    }

    func testAFlickJustBeforeTheOnsetGivesRefocus() {
        goSoft(flickSpeed: 0.4)
        XCTAssertFalse(route.instructions.contains(where: isCheckEdge))
        XCTAssertTrue(route.instructions.contains(.refocus))
    }

    func testNoReadingWithDetailInTheLookbackIsNotMoving() {
        route.startColumnOne()
        // A pause (a resume or a lost stretch) clears the history: the first blank is Refocus.
        route.guide.pause(.alignment)
        route.feed(times: 3)
        route.guide.resume(seconds: route.seconds)
        let soft = ScriptedRoute.Frame(
            viewClass: .blurry, ahead: 60, behind: 60, aheadFocus: 0.3, behindFocus: 0.3,
            sideA: 60, sideB: 60)
        route.feed(soft, times: 2)
        route.feed(blurred(still: false), times: 14)
        XCTAssertFalse(route.instructions.contains(where: isCheckEdge))
    }

    /// Test 4's top edge: positions about constant, the last detail readings moving slowly
    /// (speed 0.034), then blur whose speed is noise (0.28 up to 1.05).
    func testTheTestFourTopEdgeReplayGivesCheckEdgeFromTheFirstBlurVerdict() {
        route.startColumnOne()
        route.feed(move: ScriptedRoute.up, times: 3)
        func thin(_ speed: Double, still: Bool = false) -> ScriptedRoute.Frame {
            ScriptedRoute.Frame(viewClass: .thin, still: still, speed: speed)
        }
        route.feed(thin(0.222), times: 2)
        route.feed(thin(0.003, still: true), times: 2)
        route.feed(thin(0.004), times: 2)
        route.feed(thin(0.009), times: 2)
        route.feed(thin(0.034), times: 2)
        let soft = ScriptedRoute.Frame(
            viewClass: .blurry, ahead: 60, behind: 60, aheadFocus: 0.3, behindFocus: 0.3,
            sideA: 60, sideB: 60, speed: 0.284)
        route.feed(soft, times: 2)
        for speed in [0.489, 0.62, 0.8, 0.95, 1.047] {
            route.feed(blurred(still: false, speed: speed), times: 3)
        }
        let first = route.steps.firstIndex { isCheckEdge($0.instruction) }
        XCTAssertNotNil(first)
        if let first {
            XCTAssertTrue(
                route.steps[first...].allSatisfy { isCheckEdge($0.instruction) },
                "check edge from the first blur verdict on")
        }
        XCTAssertFalse(route.instructions.contains(.refocus))
    }

    func testSteppingBackOntoSampleThenForwardIntoBlankConfirmsTheEdgeAndTurnsTheColumn() {
        goSoft()
        XCTAssertTrue(route.instructions.contains(where: isCheckEdge))
        // Back onto sample: the normal move instruction takes over.
        route.feed(move: CGPoint(x: 0, y: 0.1), times: 3)
        XCTAssertTrue(route.last.stateName.hasPrefix("column 1 up"))
        XCTAssertEqual(route.guide.edgesGoneBack, 0, "nothing was decided by stepping back")
        // Forward again, into blank: the whole-box arrival decides (the helper travelled in).
        route.feed(move: ScriptedRoute.up, times: 8)
        route.feed(.blank, move: ScriptedRoute.up, times: 4)
        // Phase 2o: an edge is confirmed only at rest, so the helper rests on the blank.
        route.feed(.blankStill, times: 30)
        XCTAssertEqual(route.guide.edgesGoneBack, 1, "the edge is confirmed")
        XCTAssertTrue(route.instructions.contains { if case .edgeGoBack = $0 { true } else { false } })
    }

    func testABlurThatClearsAtTheSameSpotCarriesOnWithNoEdge() {
        goSoft()
        // Detail returns exactly where it was lost: nothing was decided.
        route.feed(ScriptedRoute.Frame(still: true), times: 6)
        XCTAssertEqual(route.guide.edgesGoneBack, 0)
        XCTAssertEqual(route.guide.edgesReached, 1, "only the left edge")
        XCTAssertEqual(route.last.stateName, "column 1 up")
    }

    func testCheckEdgeBecomesStillNoDetailAfterTheRefocusWait() {
        goSoft()
        route.feed(blurred(still: false), times: 70)
        XCTAssertTrue(
            route.instructions.contains { if case .stillNoDetail = $0 { true } else { false } })
    }
}
