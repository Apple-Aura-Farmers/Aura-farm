import CoreGraphics
import XCTest

@testable import AuraFarm

/// Phase 2u parts B, C and D: columns start inward from the edge they follow, spots stop short of
/// the predicted edge, the expected-edge ask, and the predicted right edge with its last column.
final class EdgePredictionRouteTests: XCTestCase {
    private func simulator(
        width: Double, height: Double, start: CGPoint? = nil,
        configure: @escaping (inout GuidedSweepThresholds) -> Void = { _ in }
    ) -> GuideSimulator {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: width, height: height)])
        let simulator = GuideSimulator(
            drop: drop, start: start ?? CGPoint(x: width / 2, y: height / 2))
        simulator.useFullCoverSlip(configure)
        return simulator
    }

    private func column(_ number: Int, in result: GuideSimulator.Result) -> [FramePlacement] {
        result.placements.filter { $0.column == number }.sorted { $0.order < $1.order }
    }

    // MARK: Part B: inward starts

    func testAfterABottomEdgeTheNextColumnStartsSixTenthsUpFromIt() {
        let result = simulator(width: 2.8, height: 2.4).run()
        let two = column(2, in: result)
        XCTAssertEqual(Double(two.first?.position.y ?? 0), 2.4 - 0.6, accuracy: 0.3, "\(two)")
        XCTAssertEqual(
            Double(two.first?.position.x ?? 0), Double(column(1, in: result).first?.position.x ?? 0) + 0.8,
            accuracy: 0.3, "the same sideways step")
    }

    func testAfterATopEdgeTheNextColumnStartsSixTenthsDownFromIt() {
        let result = simulator(width: 2.8, height: 2.4).run()
        let three = column(3, in: result)
        XCTAssertEqual(Double(three.first?.position.y ?? 0), 0.6, accuracy: 0.3, "\(three)")
    }

    // MARK: Step 3: limits from column 2, and more room after a top or bottom edge

    /// Runs a 4.6 wide slip from y = -5 to 3 and notes, per state, the targets and limit reasons.
    private func limits(
        width: Double = 4.6, until stop: String
    ) -> [String: (ys: [Double], reasons: Set<String>)] {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: -5, width: width, height: 8)])
        let sim = GuideSimulator(drop: drop, start: CGPoint(x: 1.5, y: -1))
        sim.useFullCoverSlip()
        var seen: [String: (ys: [Double], reasons: Set<String>)] = [:]
        _ = sim.run(until: { step in
            var entry = seen[step.stateName] ?? ([], [])
            if let y = step.target?.y, step.edge.spotLimitReason != "empty_ahead" {
                entry.ys.append(Double(y))
            }
            if !step.edge.spotLimitReason.isEmpty { entry.reasons.insert(step.edge.spotLimitReason) }
            seen[step.stateName] = entry
            return step.stateName == stop
        })
        return seen
    }

    func testColumnTwoStopsAtColumnOnesTopEdgePlusTheMarginWithoutATwoPointFit() throws {
        let seen = limits(until: "column 3 down")
        let two = try XCTUnwrap(seen["column 2 up"])
        // The simulator's edge lines read 0 degrees: a known angle, so the provisional limit is the
        // tilted one (here level); an unknown or over-12-degree angle gives "flat_prediction"
        // (see SlipTiltTests).
        XCTAssertTrue(two.reasons.contains("tilted_prediction"), "\(two.reasons)")
        XCTAssertFalse(two.reasons.contains("fitted_prediction"))
        // Moving up: no ordinary target above -5.0 + 0.6; the edge itself is only sought.
        let ordinary = two.ys.filter { $0 > -4.99 }
        XCTAssertGreaterThanOrEqual(ordinary.min() ?? 0, -4.4 - 0.05, "\(two.ys)")
    }

    func testWithATwoPointTrustedFitTheFittedLimitIsUsedAsBefore() throws {
        let seen = limits(until: "column 5 down")
        let four = try XCTUnwrap(seen["column 4 up"])
        XCTAssertTrue(four.reasons.contains("fitted_prediction"), "\(four.reasons)")
        XCTAssertFalse(four.reasons.contains("flat_prediction"))
    }

    func testWithAKnownEyepieceTheNextColumnStartsItsRadiusPlusMarginInFromABottomEdge() {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: 6, height: 9)])
        let sim = GuideSimulator(drop: drop, start: CGPoint(x: 3, y: 4.5))
        sim.useFullCoverSlip { $0.eyepieceRadiusFields = 1.4 }
        let result = sim.run(until: { $0.stateName.hasPrefix("column 3") })
        let two = column(2, in: result)
        XCTAssertEqual(Double(two.first?.position.y ?? 0), 9.0 - 1.55, accuracy: 0.3, "\(two)")
    }

    // MARK: Part C: predicted edges

    /// Five columns on a 4.6 x 2.4 slip: column 4 (up) has two top points and column 5 (down) two
    /// bottom ones.
    func testSpotsStopAtTheMarginBeforeThePredictedEdge() {
        let result = simulator(width: 4.6, height: 2.4).run()
        let four = column(4, in: result)
        XCTAssertGreaterThanOrEqual(four.count, 2)
        XCTAssertGreaterThan(
            four.map { Double($0.position.y) }.min() ?? 0, 0.5 - 0.25,
            "no spot beyond the predicted top edge less 0.5: \(four.map(\.position))")
        XCTAssertEqual(result.finishReason, .rightEdge)
    }

    /// Stops the run at the first reading of column 5 (down) that captured: the bottom edge is
    /// predicted from columns 1 and 3.
    private func columnFive() -> (GuideSimulator, GuideReading) {
        let sim = simulator(width: 4.6, height: 2.4)
        _ = sim.run(until: { $0.stateName == "column 5 down" && $0.capture != nil })
        // The view is well past the predicted bottom edge (2.4) with nothing ahead.
        let reading = GuideReading(
            seconds: sim.guideSeconds + 1, position: CGPoint(x: 3.8, y: 3.3), tracking: .tracking,
            unconfirmedGaps: 0, viewClass: .thin, speedFraction: 0.05, isStill: false,
            quadAheadAway: 2, quadAheadToward: 2, quadBehindAway: 100, quadBehindToward: 100,
            stillSeconds: 0)
        return (sim, reading)
    }

    func testPassingThePredictedEdgeWithNothingAheadAsksAndNeverAcceptsByItself() {
        let (sim, first) = columnFive()
        var reading = first
        for index in 0..<40 {
            reading.seconds += 0.1
            let step = sim.guide.update(reading)
            if index > 0 { XCTAssertEqual(step.instruction, .expectedEdge) }
            XCTAssertTrue(index == 0 || step.edge.expectedEdgeAsk)
        }
        XCTAssertEqual(sim.guide.update(reading).stateName, "column 5 down")
        XCTAssertFalse(sim.guide.isFinished)
    }

    func testTheCheckMarkTakesThePredictedEdgeAndEndsTheLeg() throws {
        let (sim, first) = columnFive()
        var reading = first
        reading.seconds += 0.1
        XCTAssertEqual(sim.guide.update(reading).instruction, .expectedEdge)
        let edgesBefore = sim.guide.edgesReached
        let answer = sim.guide.userEdge(.yes, reading)
        XCTAssertEqual(answer.instruction, .edgeReached)
        XCTAssertEqual(sim.guide.edgesReached, edgesBefore + 1)
        XCTAssertNotEqual(answer.stateName, "column 5 down")
    }

    func testTheCrossKeepsGoingAndDoesNotAskAgainInThatLeg() {
        let (sim, first) = columnFive()
        var reading = first
        reading.seconds += 0.1
        XCTAssertEqual(sim.guide.update(reading).instruction, .expectedEdge)
        XCTAssertEqual(sim.guide.userEdge(.no, reading).instruction, .notAnEdge)
        for _ in 0..<60 {
            reading.seconds += 0.1
            XCTAssertNotEqual(sim.guide.update(reading).instruction, .expectedEdge)
        }
        XCTAssertFalse(sim.guide.isFinished)
    }

    func testAnAreaAheadFullOfDetailDoesNotAsk() {
        let (sim, first) = columnFive()
        var reading = first
        reading.quadAheadAway = 90
        reading.quadAheadToward = 90
        reading.seconds += 0.1
        XCTAssertNotEqual(sim.guide.update(reading).instruction, .expectedEdge)
    }

    // MARK: Part D: the right edge and the last column

    private func squareRun(square: Bool) -> (GuideSimulator, GuideSimulator.Result) {
        let sim = simulator(width: 5.6, height: 5.6, start: CGPoint(x: 2.0, y: 2.0)) {
            $0.columnSpacingFields = 1.6
            $0.squareCoverSlip = square
        }
        return (sim, sim.run())
    }

    func testASquareSlipShortensTheStepThatWouldCrossTheRightEdgeAndFinishesAfterTheLastColumn() {
        let (sim, result) = squareRun(square: true)
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertEqual(sim.guide.rightEdgeSource, "predicted")
        let last = column(4, in: result)
        XCTAssertFalse(last.isEmpty, "a last column: \(result.states)")
        XCTAssertEqual(Double(last.first?.position.x ?? 0), 5.6 - 0.6, accuracy: 0.4)
        XCTAssertTrue(column(5, in: result).isEmpty)
        XCTAssertNotNil(sim.guide.predictedEdges.rightX)
        XCTAssertEqual(sim.guide.predictedEdges.rightX ?? 0, 5.6, accuracy: 0.4)
    }

    func testAnUnknownSlipHasNoRightEdgePredictionAndTheLineFindsIt() {
        let (sim, result) = squareRun(square: false)
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertEqual(sim.guide.rightEdgeSource, "line")
    }

    /// Stops on the first reading of the first step right and walks the view `past` fields beyond
    /// the column just done into empty glass, for `seconds`.
    private func emptyStep(past: Double, seconds: Double) -> (GuideSimulator, GuideStep) {
        let sim = simulator(width: 5.6, height: 5.6, start: CGPoint(x: 2.0, y: 2.0)) {
            $0.columnSpacingFields = 1.6
        }
        _ = sim.run(until: { $0.stateName == "step right" })
        let baseX = Double(sim.guide.placements.last?.position.x ?? 0)
        let y = Double(sim.guide.placements.last?.position.y ?? 0)
        var reading = GuideReading(
            seconds: sim.guideSeconds, position: CGPoint(x: baseX + past, y: y), tracking: .tracking,
            unconfirmedGaps: 0, viewClass: .thin, speedFraction: 0.05, isStill: false,
            quadAheadAway: 2, quadAheadToward: 2, quadBehindAway: 100, quadBehindToward: 100,
            stillSeconds: 0)
        var step = sim.guide.update(reading)
        var elapsed = 0.0
        while elapsed < seconds {
            elapsed += 0.1
            reading.seconds += 0.1
            step = sim.guide.update(reading)
        }
        return (sim, step)
    }

    func testAStepRightIntoEmptyGlassMoreThanEightTenthsPastPlacesOneLastColumn() {
        let (sim, step) = emptyStep(past: 1.0, seconds: 1.3)
        XCTAssertFalse(sim.guide.isFinished)
        XCTAssertEqual(sim.guide.rightEdgeSource, "empty")
        let base = Double(sim.guide.placements.last?.position.x ?? 0)
        XCTAssertEqual(Double(step.target?.x ?? 0), base + 1.0 - 0.6, accuracy: 0.05)
    }

    func testAStepRightIntoEmptyGlassWithinEightTenthsPastFinishes() {
        let (sim, _) = emptyStep(past: 0.5, seconds: 1.3)
        XCTAssertTrue(sim.guide.isFinished)
        XCTAssertEqual(sim.guide.finishReason, .rightEdge)
        XCTAssertEqual(sim.guide.rightEdgeSource, "empty")
    }

    func testAnEmptyStretchShorterThanASecondDecidesNothing() {
        let (sim, _) = emptyStep(past: 1.0, seconds: 0.5)
        XCTAssertFalse(sim.guide.isFinished)
        XCTAssertEqual(sim.guide.rightEdgeSource, "")
    }

    func testARecordFromBeforeTheRightEdgeSourceStillDecodes() throws {
        let old = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":0.8,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{},"tallyCountsByLabel":{},"totalCount":0,
            "minimumConfidence":0.3,"cropToEyepiece":false,"classNames":[],"framesCounted":1,
            "framesSkippedByReason":{}}
            """
        let record = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(old.utf8))
        XCTAssertEqual(record.rightEdgeSource, "")
    }

    // MARK: Phase 3a part B: never too far with the line ahead

    /// Column 5 (down) just captured; the view is `past` fields beyond its next spot, with an
    /// accepted line `line` fields ahead of the cross when given.
    private func pastTheSpot(
        past: Double = 0.8, line: Double? = nil, still: Double = 0
    ) -> GuideStep {
        let sim = simulator(width: 4.6, height: 2.4)
        _ = sim.run(until: { $0.stateName == "column 5 down" && $0.capture != nil })
        let last = sim.guide.placements.last?.position ?? .zero
        func reading(y: Double) -> GuideReading {
            GuideReading(
                seconds: sim.guideSeconds + 1, position: CGPoint(x: 3.8, y: y), tracking: .tracking,
                unconfirmedGaps: 0, viewClass: .sample, speedFraction: 0.05, isStill: still > 0,
                quadAheadAway: 90, quadAheadToward: 90, quadBehindAway: 100, quadBehindToward: 100,
                stillSeconds: still,
                edgeLine: line.map {
                    EdgeLine(
                        strength: 12, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: $0,
                        sign: 1, slideResidualFields: 0.05, path: [], isCandidate: true)
                })
        }
        let target = sim.guide.update(reading(y: Double(last.y))).target?.y ?? 0
        return sim.guide.update(reading(y: Double(target) + past))
    }

    func testPastASpotWithNoLineTheViewIsStillTooFar() {
        let step = pastTheSpot(past: 0.8)
        XCTAssertEqual(step.instruction, .tooFar, "away from an edge line nothing changed")
    }

    func testWithAnAcceptedLineAheadTheViewIsNeverTooFar() {
        for line in [0.1, 0.3, 0.5] {
            let step = pastTheSpot(past: 0.8, line: line)
            if case .tooFar = step.instruction { XCTFail("too far with a line \(line) ahead") }
            if case .otherWay = step.instruction { XCTFail("other way with a line \(line) ahead") }
        }
        guard case .lineLead(let direction, false) = pastTheSpot(past: 0.8, line: 0.4).instruction
        else { return XCTFail("a little further expected") }
        XCTAssertEqual(Double(direction.y), 1, "along the down leg")
    }

    func testStillWithTheLineAheadBeyondTheCrossBandNudges() {
        guard case .lineLead(_, true) = pastTheSpot(past: 0.8, line: 0.4, still: 2.5).instruction
        else { return XCTFail("nudge expected") }
        if case .lineLead(_, true) = pastTheSpot(past: 0.8, line: 0.4, still: 1.0).instruction {
            XCTFail("a nudge needs 2 s")
        }
        if case .lineLead(_, true) = pastTheSpot(past: 0.8, line: 0.2, still: 2.5).instruction {
            XCTFail("no nudge inside the at-cross band")
        }
    }

    /// A slip whose bottom is 1 field lower from x = 2.6 on: the bottom edge predicted from the
    /// first columns is 1 field short of the real one at column 5.
    func testALegWhosePredictedEdgeIsOneFieldShortStillReachesTheRealLine() {
        let drop = SimulatedDrop(
            circles: [],
            rects: [
                CGRect(x: 0, y: 0, width: 2.6, height: 2.4), CGRect(x: 2.6, y: 0, width: 2.4, height: 3.4),
            ])
        let sim = GuideSimulator(drop: drop, start: CGPoint(x: 1.5, y: 1.2))
        sim.useFullCoverSlip()
        let result = sim.run()
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertFalse(result.instructions.contains(.tooFar))
        let five = column(5, in: result)
        XCTAssertFalse(five.isEmpty)
        // Column 6 starts 0.6 inside the bottom edge column 5 ended on: the real line at 3.4.
        let six = column(6, in: result)
        if let first = six.first {
            XCTAssertEqual(Double(first.position.y), 3.4 - 0.6, accuracy: 0.35, "\(six)")
        }
    }

    // MARK: Phase 3a part C: a mark goes to the line

    func testMarkEdgePutsTheEdgeAtTheAcceptedLineNotWhereTheHelperStood() {
        let sim = simulator(width: 4.6, height: 2.4)
        _ = sim.run(until: { $0.stateName == "column 5 down" && $0.capture != nil })
        let at = Double(sim.guide.placements.last?.position.y ?? 0)
        let line = EdgeLine(
            strength: 12, coverage: 1, longestRun: 8, angleDegrees: 0, offsetFields: 0.3, sign: 1,
            slideResidualFields: 0.05, path: [], isCandidate: true)
        let reading = GuideReading(
            seconds: sim.guideSeconds + 1, position: CGPoint(x: 3.8, y: at), tracking: .tracking,
            unconfirmedGaps: 0, viewClass: .sample, speedFraction: 0.05, isStill: false,
            quadAheadAway: 90, quadAheadToward: 90, quadBehindAway: 100, quadBehindToward: 100,
            edgeLine: line)
        _ = sim.guide.update(reading)
        _ = sim.guide.userEdge(.mark, reading)
        var stepTarget: Double?
        var finishedLeg = reading
        finishedLeg.edgeLine = nil
        for _ in 0..<80 where stepTarget == nil {
            finishedLeg.seconds += 0.1
            let step = sim.guide.update(finishedLeg)
            if step.stateName == "step right" { stepTarget = step.target.map { Double($0.y) } }
        }
        // The edge is the line 0.3 below the view; the next column starts 0.6 up from it.
        XCTAssertEqual(stepTarget ?? .nan, at + 0.3 - 0.6, accuracy: 0.05)
    }

    // MARK: Phase 3a part D: the right-edge source is always recorded

    func testALastColumnPlacedFromAnEmptyViewKeepsItsSourceWhenItFinishes() {
        let (sim, _) = emptyStep(past: 1.0, seconds: 1.3)
        XCTAssertFalse(sim.guide.isFinished)
        let result = sim.run()
        XCTAssertTrue(result.finished)
        XCTAssertEqual(sim.guide.finishReason, .rightEdge)
        XCTAssertEqual(sim.guide.rightEdgeSource, "empty")
    }

    func testEveryRightEdgeFinishInTheSimulatedRunsNamesItsSource() {
        for square in [true, false] {
            let (sim, result) = squareRun(square: square)
            XCTAssertEqual(result.finishReason, .rightEdge)
            XCTAssertFalse(sim.guide.rightEdgeSource.isEmpty)
        }
    }

    func testTheRunRecordCarriesTheRightEdgeSource() throws {
        let json = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":1.6,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{},"tallyCountsByLabel":{},"totalCount":0,
            "minimumConfidence":0.3,"cropToEyepiece":false,"classNames":[],"framesCounted":1,
            "framesSkippedByReason":{},"rightEdgeSource":"predicted"}
            """
        var record = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(json.utf8))
        XCTAssertEqual(record.rightEdgeSource, "predicted")
        record.rightEdgeSource = "line"
        let data = try GuideRunRecord.encoder().encode(record)
        XCTAssertEqual(
            try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data).rightEdgeSource, "line")
    }
}
