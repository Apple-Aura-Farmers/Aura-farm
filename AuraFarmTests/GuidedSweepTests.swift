import XCTest

@testable import AuraFarm

final class GuidedSweepTests: XCTestCase {
    private func run(
        _ drop: SimulatedDrop, from start: CGPoint, configure: (GuideSimulator) -> Void = { _ in }
    ) -> GuideSimulator.Result {
        let simulator = GuideSimulator(drop: drop, start: start)
        configure(simulator)
        return simulator.run()
    }

    private func report(_ name: String, _ result: GuideSimulator.Result) {
        print(
            String(
                format:
                    "SIM %@: readings %d finished %@ reason %@ captures %d coverage %.1f%% columns %d rechecks %d failed probes %d",
                name, result.readings, "\(result.finished)", "\(String(describing: result.finishReason))",
                result.placements.count, result.coverage * 100,
                Set(result.placements.map(\.column)).count, result.rechecks, result.failedProbes))
    }

    private let round3 = SimulatedDrop(circles: [(CGPoint(x: 0, y: 0), 3)])

    func testRoundDropStartingAtTheCentre() {
        let result = run(round3, from: .zero)
        report("round r=3 centre", result)
        XCTAssertTrue(result.finished)
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
        XCTAssertLessThan(result.readings, 20000)
    }

    func testRoundDropStartingNearTheTopRechecksTheLeftEdge() {
        let result = run(round3, from: CGPoint(x: 0, y: -2.5))
        report("round r=3 near top", result)
        XCTAssertTrue(result.states.contains("recheck: to middle"), "\(result.states)")
        XCTAssertTrue(result.finished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testAnOffCentreDrop() {
        let drop = SimulatedDrop(circles: [(CGPoint(x: 4, y: -2), 2.5)])
        let result = run(drop, from: CGPoint(x: 4.2, y: -1.5))
        report("off-centre r=2.5", result)
        XCTAssertTrue(result.finished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testASmallDrop() {
        let drop = SimulatedDrop(circles: [(.zero, 1)])
        let result = run(drop, from: .zero)
        report("small r=1", result)
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testALargeDrop() {
        let drop = SimulatedDrop(circles: [(.zero, 6)])
        let result = run(drop, from: CGPoint(x: 1, y: 1))
        report("large r=6", result)
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testAnElongatedDrop() {
        let drop = SimulatedDrop(circles: [(CGPoint(x: -2, y: 0), 2.5), (CGPoint(x: 2, y: 0), 2.5)])
        let result = run(drop, from: CGPoint(x: 0, y: 0))
        report("elongated", result)
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testABlankStartFindsTheSampleFirst() {
        let drop = SimulatedDrop(circles: [(CGPoint(x: 6, y: 0), 2.5)])
        let result = run(drop, from: .zero) { $0.searchTarget = CGPoint(x: 6, y: 0) }
        report("blank start", result)
        XCTAssertEqual(result.states.first, "find sample")
        XCTAssertTrue(result.instructions.prefix(10).allSatisfy { $0 == .findSample })
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testADropWithAHoleFinishesAndHasKnownGaps() {
        let drop = SimulatedDrop(circles: [(.zero, 3.5)], holes: [(CGPoint(x: 0.5, y: 0), 0.8)])
        let result = run(drop, from: CGPoint(x: 2, y: 2))
        report("hole", result)
        XCTAssertTrue(result.finished, "a hole must not trap the route")
        XCTAssertGreaterThan(result.coverage, 0.7)
    }

    func testWrongWayIsToldAndCorrected() {
        let result = run(round3, from: .zero) { $0.wrongWayFields = 0.5 }
        report("wrong way", result)
        XCTAssertTrue(result.instructions.contains(.otherWay))
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
    }

    func testOvershootIsToldTooFar() {
        let result = run(round3, from: .zero) { $0.overshootFields = 0.5 }
        report("overshoot", result)
        XCTAssertTrue(result.instructions.contains(.tooFar))
        XCTAssertEqual(result.finishReason, .sampleFinished)
    }

    func testLostTrackingSaysSlowDownAndPlacementsAreCertainWhenNoGapRose() {
        let result = run(round3, from: .zero) { $0.lostAtReading = 400 }
        report("lost, no gap", result)
        XCTAssertTrue(result.instructions.contains(.slowDown))
        XCTAssertEqual(result.finishReason, .sampleFinished)
        XCTAssertFalse(result.placements.contains { $0.uncertain })
    }

    func testPlacementsAfterAGapAreUncertainWithinThatColumn() {
        let result = run(round3, from: .zero) {
            $0.lostAtReading = 400
            $0.lostRaisesGap = true
        }
        report("lost, gap", result)
        XCTAssertTrue(result.instructions.contains(.slowDown))
        XCTAssertTrue(result.placements.contains { $0.uncertain })
        XCTAssertTrue(result.placements.contains { !$0.uncertain }, "earlier columns stay certain")
    }

    func testNoTwoCapturesAreCloserThanTheDuplicateDistance() {
        for (name, drop, start) in [
            ("round", round3, CGPoint.zero),
            ("near top", round3, CGPoint(x: 0, y: -2.5)),
        ] {
            let result = run(drop, from: start)
            let limit = GuidedSweepThresholds().duplicateSpotFields
            for (index, a) in result.placements.enumerated() {
                for b in result.placements[(index + 1)...] {
                    XCTAssertGreaterThanOrEqual(
                        hypot(Double(a.position.x - b.position.x), Double(a.position.y - b.position.y)),
                        limit - 0.15, "\(name): captures \(a.order) and \(b.order) are too close")
                }
            }
        }
    }

    func testFinishingByTheHelperStopsAtOnce() {
        var guide = GuidedSweep()
        let reading = GuideReading(
            seconds: 0, position: .zero, tracking: .tracking, unconfirmedGaps: 0, viewClass: .sample,
            speedFraction: 0, isStill: true)
        XCTAssertNotEqual(guide.update(reading).instruction, .finished)
        guide.finish(reason: .endedByHelper)
        let step = guide.update(reading)
        XCTAssertEqual(step.instruction, .finished)
        XCTAssertTrue(step.isFinished)
        XCTAssertEqual(step.finishReason, .endedByHelper)
        guide.finish(reason: .storageFull)
        XCTAssertEqual(guide.finishReason, .endedByHelper, "the first reason stands")
    }

    func testTheRouteStartsByFindingSampleThenTravelsLeft() {
        var guide = GuidedSweep()
        func reading(_ viewClass: ViewClass) -> GuideReading {
            GuideReading(
                seconds: 0, position: .zero, tracking: .tracking, unconfirmedGaps: 0, viewClass: viewClass,
                speedFraction: 0, isStill: true)
        }
        XCTAssertEqual(guide.update(reading(.blank)).instruction, .findSample)
        XCTAssertEqual(guide.update(reading(.sample)).instruction, .travel(direction: CGPoint(x: -1, y: 0)))
        XCTAssertEqual(guide.update(reading(.thin)).stateName, "find left edge")
    }
}
