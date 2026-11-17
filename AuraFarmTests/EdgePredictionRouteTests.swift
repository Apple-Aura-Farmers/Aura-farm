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
}
