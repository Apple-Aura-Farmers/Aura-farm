import XCTest

@testable import AuraFarm

/// Phase 2f: columns run edge to edge. Column 1 starts inside the left edge, only an edge AHEAD
/// ends a leg (contrast, side balance, holding on a spot), and a long blur is decided when
/// detail comes back, never by a timer. 10 readings a second, scripted in screen axes.
final class SlideRouteColumnTests: XCTestCase {
    private var guide = GuidedSweep()
    private var seconds = 0.0
    private var position = CGPoint.zero
    private var steps: [GuideStep] = []
    private var returnCount = 0
    private var lastReturn = BlankReturnOutcome.none

    private struct Frame {
        var viewClass = ViewClass.sample
        var tracking = TrackingState.tracking
        var ahead: Double? = 400
        var behind: Double? = 400
        var aheadFocus: Double? = 1
        var behindFocus: Double? = 0.95
        var sideA: Double? = 400
        var sideB: Double? = 400
        var still = false
    }

    /// Feeds `times` readings, the view moving `move` fields on each.
    private func feed(_ frame: Frame, move: CGPoint = .zero, times: Int = 1) {
        for _ in 0..<times {
            seconds += 0.1
            position = CGPoint(x: position.x + move.x, y: position.y + move.y)
            steps.append(
                guide.update(
                    GuideReading(
                        seconds: seconds, position: position, tracking: frame.tracking,
                        unconfirmedGaps: 0, viewClass: frame.viewClass, speedFraction: 0.05,
                        isStill: frame.still, aheadSharpness: frame.ahead,
                        behindSharpness: frame.behind, aheadFocusRatio: frame.aheadFocus,
                        behindFocusRatio: frame.behindFocus, sideSharpnessA: frame.sideA,
                        sideSharpnessB: frame.sideB, lastBlankReturn: lastReturn,
                        blankReturnCount: returnCount)))
        }
    }

    private var instructions: [GuideInstruction] { steps.map(\.instruction) }
    private var last: GuideStep { steps[steps.count - 1] }

    private func isGoBack(_ instruction: GuideInstruction) -> Bool {
        if case .edgeGoBack = instruction { return true }
        return false
    }

    private func isStillNoDetail(_ instruction: GuideInstruction) -> Bool {
        if case .stillNoDetail = instruction { return true }
        return false
    }

    private let left = CGPoint(x: -0.05, y: 0)
    private let up = CGPoint(x: 0, y: -0.1)
    private let right = CGPoint(x: 0.1, y: 0)

    /// Travels left onto sample, finds the left edge at the centre cross, goes to the first
    /// spot of column 1 and captures it. Returns the x the edge was found at.
    @discardableResult
    private func startColumnOne() throws -> Double {
        feed(Frame(), move: left, times: 15)
        feed(Frame(ahead: 50, behind: 250, still: true), times: 14)
        let reached = try XCTUnwrap(steps.first { $0.instruction == .edgeReached })
        XCTAssertEqual(reached.stateName, "column 1 up")
        let edgeX = Double(position.x)
        feed(Frame(), move: right, times: 6)
        feed(Frame(still: true), times: 14)
        XCTAssertTrue(instructions.contains(.captured), "first spot captured")
        return edgeX
    }

    // MARK: a) the inset

    func testA_theLeftEdgeAtTheCentreStartsColumnOneInsideIt() throws {
        feed(Frame(), move: left, times: 15)
        feed(Frame(ahead: 50, behind: 250, still: true), times: 14)
        let reached = try XCTUnwrap(steps.first { $0.instruction == .edgeReached })
        let target = try XCTUnwrap(reached.target)
        XCTAssertEqual(Double(target.x), Double(position.x) + 0.6, accuracy: 1e-9, "edge x + 0.6")
        XCTAssertEqual(Double(target.y), Double(position.y), accuracy: 1e-9, "on the same row")
        XCTAssertEqual(reached.stateName, "column 1 up")
        // The first capture is at the inset spot, not at the edge.
        feed(Frame(), move: right, times: 6)
        feed(Frame(still: true), times: 14)
        let first = try XCTUnwrap(guide.placements.first)
        XCTAssertEqual(Double(first.position.x), Double(target.x), accuracy: 0.15)
    }

    func testAWholeBoxOvershootStillStartsColumnOneAtTheFirstSampleBack() throws {
        feed(Frame(), move: left, times: 15)
        // Overshot: nothing to follow, the last tracked half behind was sharp: go back.
        feed(
            Frame(
                viewClass: .blank, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
                behindFocus: nil, sideA: nil, sideB: nil), times: 25)
        XCTAssertTrue(instructions.contains(where: isGoBack))
        let backAt = position
        feed(Frame(), move: right, times: 3)
        let target = try XCTUnwrap(last.target)
        XCTAssertEqual(last.stateName, "column 1 up")
        XCTAssertEqual(Double(target.x), Double(backAt.x) + 0.3, accuracy: 0.31, "no inset")
        XCTAssertLessThan(Double(target.x), Double(backAt.x) + 0.45)
    }

    // MARK: b) holding on a spot is not an edge

    func testB_bothHalvesHoveringAroundTheCutNeverEndTheLeg() throws {
        try startColumnOne()
        for _ in 0..<4 {
            // Up to the next spot with the top and bottom halves hovering, then hold on it.
            for index in 0..<8 {
                let hover = Frame(ahead: index % 2 == 0 ? 110 : 140, behind: index % 2 == 0 ? 140 : 110)
                feed(hover, move: up)
            }
            for index in 0..<12 {
                feed(
                    Frame(ahead: index % 2 == 0 ? 110 : 140, behind: index % 2 == 0 ? 140 : 110, still: true))
            }
        }
        XCTAssertEqual(guide.edgesReached, 1, "only the left edge")
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertEqual(last.stateName, "column 1 up")
        XCTAssertGreaterThanOrEqual(guide.placements.count, 4, "captures carried on up the column")
        XCTAssertTrue(steps.contains { $0.edge.reason == "halves_too_close" })
    }

    func testB_aCandidateThatBeginsAsTheHelperReachesASpotBuildsNothingFromHolding() throws {
        try startColumnOne()
        let before = guide.placements.count
        feed(Frame(), move: up, times: 8)  // onto the next spot
        // Clear contrast, but only now, as the spot is reached: the stillness is the hold.
        feed(Frame(ahead: 100, behind: 250, still: true), times: 12)
        XCTAssertEqual(guide.edgesReached, 1)
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertTrue(steps.contains { $0.edge.reason == "spot_hold" })
        XCTAssertEqual(guide.placements.count, before + 1, "the spot was captured instead")
        XCTAssertEqual(last.stateName, "column 1 up")
    }

    // MARK: c) a side drifting into view

    func testC_aClearSideDifferenceIsNotTheTopEdge() throws {
        try startColumnOne()
        // Left half 40, right 400: the cover slip's side is drifting in. Top and bottom differ
        // clearly (so only the side rule rejects this).
        feed(Frame(), move: up, times: 4)
        feed(Frame(ahead: 100, behind: 250, sideA: 40, sideB: 400, still: true), times: 20)
        XCTAssertEqual(guide.edgesReached, 1)
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertTrue(steps.suffix(20).allSatisfy { $0.edge.reason == "side_imbalance" })
        XCTAssertEqual(last.stateName, "column 1 up")

        // Top and bottom both about 150: no candidate at all.
        feed(Frame(ahead: 150, behind: 150, sideA: 40, sideB: 400, still: true), times: 20)
        XCTAssertEqual(guide.edgesReached, 1)
        XCTAssertEqual(last.stateName, "column 1 up")
    }

    // MARK: d) a real top edge

    func testD_aRealTopEdgeEndsTheLegAndTheColumnTurnsDown() throws {
        try startColumnOne()
        feed(Frame(), move: up, times: 6)
        feed(Frame(ahead: 50, behind: 300, sideA: 300, sideB: 300, still: true), times: 14)
        XCTAssertEqual(guide.edgesReached, 2, "the left edge and the top edge")
        XCTAssertTrue(steps.contains { $0.edge.verdict == "confirmed" && $0.edge.reason == "arrived" })
        // The end spot is taken where the edge was found, then the column comes back down.
        feed(Frame(still: true), times: 14)
        XCTAssertEqual(last.stateName, "column 1 down")
        XCTAssertFalse(instructions.contains(where: isGoBack))
    }

    // MARK: e, f) a long blur

    /// A focus slip in the middle of a leg: two tracked readings already blurred, then nothing
    /// to follow, the helper still.
    private func slip(seconds duration: Double) {
        // At rest before the picture goes (Phase 2i: motion is judged from the readings with
        // detail before the onset; a helper still moving then is told to step back instead).
        feed(Frame(still: true), times: 6)
        feed(
            Frame(
                viewClass: .blurry, ahead: 60, behind: 60, aheadFocus: 0.3, behindFocus: 0.3,
                sideA: 60, sideB: 60, still: true), times: 2)
        feed(
            Frame(
                viewClass: .blurry, tracking: .paused, ahead: nil, behind: nil, aheadFocus: nil,
                behindFocus: nil, sideA: nil, sideB: nil, still: true),
            times: Int(duration * 10))
    }

    func testE_aTenSecondFocusSlipThenTheSamePlaceCarriesOn() throws {
        try startColumnOne()
        feed(Frame(), move: up, times: 5)
        let target = try XCTUnwrap(last.target)
        slip(seconds: 10)
        XCTAssertTrue(instructions.contains(.refocus))
        let noDetail = try XCTUnwrap(steps.firstIndex { isStillNoDetail($0.instruction) })
        let refocus = try XCTUnwrap(steps.lastIndex { $0.instruction == .refocus })
        XCTAssertLessThan(refocus, noDetail, "refocus first, then still no detail after 6 s")
        XCTAssertTrue(steps.suffix(30).allSatisfy { isStillNoDetail($0.instruction) })
        XCTAssertTrue(steps.contains { $0.edge.reason == "timeout_no_detail" })
        XCTAssertEqual(guide.edgesReached, 1)
        XCTAssertEqual(guide.edgesGoneBack, 0)
        XCTAssertEqual(last.stateName, "column 1 up", "nothing was decided")

        // Detail is back, the tracker matched the picture, and it is the same spot.
        returnCount += 1
        lastReturn = .matched
        feed(Frame(still: true), times: 3)
        XCTAssertEqual(guide.edgesGoneBack, 0)
        XCTAssertFalse(instructions.contains(where: isGoBack))
        XCTAssertEqual(last.stateName, "column 1 up")
        XCTAssertEqual(last.target, target, "carries on to the same target")
        XCTAssertTrue(steps.contains { $0.edge.reason == "same_spot" })
    }

    func testF_anUnmatchedOrMovedReturnAfterALongBlurEndsTheLeg() throws {
        for (name, outcome, jump) in [
            ("unmatched", BlankReturnOutcome.unmatched, 0.0),
            ("matched but 0.5 field away", BlankReturnOutcome.matched, -0.5),
        ] {
            guide = GuidedSweep()
            (seconds, position, steps, returnCount, lastReturn) = (0, .zero, [], 0, .none)
            try startColumnOne()
            feed(Frame(), move: up, times: 6)
            slip(seconds: 10)
            XCTAssertEqual(last.stateName, "column 1 up", name)
            returnCount += 1
            lastReturn = outcome
            position.y += CGFloat(jump)
            feed(Frame(still: true), times: 3)
            XCTAssertEqual(guide.edgesGoneBack, 1, name)
            XCTAssertNotEqual(last.stateName, "column 1 up", "\(name): the leg ended there")
            XCTAssertTrue(last.stateName.hasPrefix("column 1"), "\(name): \(last.stateName)")
        }
    }

    // MARK: Unit: EdgeConfirmation

    func testHoldingOnASpotBuildsNoConfirmProgressButAnEarlierCandidateStillConfirms() {
        func run(since: Double, reachedAt: Double?) -> EdgeVerdict {
            var confirmation = EdgeConfirmation()
            var verdict = EdgeVerdict.none
            for index in 0..<30 {
                let now = Double(index) * 0.1
                let reading = GuideReading(
                    seconds: now, position: CGPoint(x: 0, y: -0.1 * min(now, 1)), tracking: .tracking,
                    unconfirmedGaps: 0, viewClass: .thin, speedFraction: 0.05, isStill: now >= 1,
                    aheadSharpness: 50, behindSharpness: 300, aheadFocusRatio: 1,
                    behindFocusRatio: 0.95)
                verdict = confirmation.update(
                    reading: reading, heading: CGPoint(x: 0, y: -1), candidate: .halfEdge,
                    since: since, spotReachedAt: reachedAt)
            }
            return verdict
        }
        XCTAssertEqual(run(since: 0.9, reachedAt: 1.0), .none, "began as the spot was reached")
        XCTAssertEqual(run(since: 1.0, reachedAt: 0.9), .none, "began after reaching it")
        XCTAssertEqual(run(since: 0.2, reachedAt: 1.0), .confirmed, "began on the way there")
        XCTAssertEqual(run(since: 0.9, reachedAt: nil), .confirmed, "no spot, no hold")
    }

    func testTheSidesAreTheHalvesAcrossTheHeading() throws {
        let halves = BoxHalves(left: 10, right: 20, top: 30, bottom: 40)
        let vertical = try XCTUnwrap(halves.sideSharpness(forFrameDirection: CGPoint(x: 0, y: -1)))
        XCTAssertEqual([vertical.a, vertical.b].sorted(), [10, 20])
        let horizontal = try XCTUnwrap(halves.sideSharpness(forFrameDirection: CGPoint(x: 1, y: 0)))
        XCTAssertEqual([horizontal.a, horizontal.b].sorted(), [30, 40])
        XCTAssertNil(halves.sideSharpness(forFrameDirection: .zero))
        let sides = try XCTUnwrap(BoxHalves.sides(forFrameDirection: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(sides.0, .top)
        XCTAssertEqual(sides.1, .bottom)
    }

    // MARK: Simulator: a skewed cover slip

    /// The vertical extent of the sample on the line `x`.
    private func extent(of drop: SimulatedDrop, atX x: Double) -> (top: Double, bottom: Double)? {
        let inside = stride(from: -8.0, through: 8.0, by: 0.01).filter {
            drop.contains(CGPoint(x: x, y: $0))
        }
        guard let top = inside.first, let bottom = inside.last else { return nil }
        return (top, bottom)
    }

    func testSkewedSquareColumnsRunEdgeToEdge() {
        let drop = SimulatedDrop.skewedSquare(from: CGPoint(x: -4, y: -4), side: 8, degrees: 2)
        let simulator = GuideSimulator(drop: drop, start: .zero)
        simulator.soil = true
        let result = simulator.run(maxReadings: 30000)
        var worst = 0.0
        var worstColumn = 0
        let columns = Set(result.placements.map(\.column))
        for column in columns.sorted() {
            let points = zip(result.placements, result.capturedTruth).filter { $0.0.column == column }
                .map(\.1)
            guard let first = points.first,
                let line = extent(of: drop, atX: Double(first.x))
            else { continue }
            let top = points.map { Double($0.y) }.min() ?? 0
            let bottom = points.map { Double($0.y) }.max() ?? 0
            let shortfall = max(top - line.top, line.bottom - bottom, 0)
            if shortfall > worst {
                worst = shortfall
                worstColumn = column
            }
        }
        print(
            String(
                format:
                    "SKEW square 8x8 2deg: readings %d finished %@ coverage %.1f%% columns %d worst shortfall %.2f (column %d) edges reached %d gone back %d false %d",
                result.readings, "\(result.finished)", result.coverage * 100, columns.count, worst,
                worstColumn, result.edgesReached, result.edgesGoneBack, result.falseEdges))
        XCTAssertTrue(result.finished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
        XCTAssertLessThanOrEqual(worst, 1.0, "every leg runs to within a field of both edges")
    }
}
