import XCTest

@testable import AuraFarm

/// Cover slip edge detection on a soil slide (E1): low detail of any class is the edge, it
/// needs a duration, and refocus never blocks it.
final class SlideRouteEdgeTests: XCTestCase {
    private var guide = GuidedSweep()
    private var seconds = 0.0
    private var position = CGPoint.zero
    private var index = 0
    private var steps: [(index: Int, step: GuideStep)] = []

    private func feed(
        _ viewClass: ViewClass, _ tracking: TrackingState, dx: Double = 0, times: Int = 1
    ) {
        for _ in 0..<times {
            seconds += 0.1
            index += 1
            position.x += dx
            let step = guide.update(
                GuideReading(
                    seconds: seconds, position: position, tracking: tracking, unconfirmedGaps: 0,
                    viewClass: viewClass, speedFraction: 0.05, isStill: false))
            steps.append((index, step))
        }
    }

    private func isEdgeGoBack(_ instruction: GuideInstruction) -> Bool {
        if case .edgeGoBack = instruction { return true }
        return false
    }

    private func isStillNoDetail(_ instruction: GuideInstruction) -> Bool {
        if case .stillNoDetail = instruction { return true }
        return false
    }

    func testE1ShapedEdgeFlickerThenSolidLowDetail() throws {
        feed(.sample, .tracking, dx: -0.1, times: 10)
        let flicker1 = index + 1
        feed(.blurry, .paused, times: 6)  // 0.6 s
        feed(.thin, .matching, times: 4)  // 0.4 s
        let flicker2 = index + 1
        feed(.blurry, .paused, times: 16)  // 1.6 s
        feed(.blurry, .paused, times: 80)  // the solid stretch

        XCTAssertFalse(steps.contains { $0.step.instruction == .refocus }, "refocus never shows")
        let edge = try XCTUnwrap(steps.first { $0.step.stateName == "edge: go back" }).index
        XCTAssertGreaterThanOrEqual(edge, flicker2 + 8, "not during the 0.6 s flicker")
        XCTAssertLessThan(edge, flicker2 + 16, "during the 1.6 s one")
        XCTAssertGreaterThan(edge, flicker1 + 6)
        let still = try XCTUnwrap(steps.first { isStillNoDetail($0.step.instruction) }).index
        print("E1 SCRIPT: edge fired at reading \(edge), stillNoDetail at reading \(still)")
        XCTAssertGreaterThan(still - edge, 60, "only after refocusAfterSeconds of low detail")
        XCTAssertLessThan(still - edge, 70)
        XCTAssertTrue(
            steps.filter { $0.index > edge && $0.index < still }.allSatisfy {
                isEdgeGoBack($0.step.instruction)
            })

        feed(.sample, .tracking, dx: 0.1, times: 2)
        XCTAssertTrue(try XCTUnwrap(steps.last).step.stateName.hasPrefix("column 1"))
    }

    func testALowDetailFlickerInsideAColumnLegDoesNotEndTheLeg() {
        feed(.sample, .tracking, dx: -0.1, times: 5)
        feed(.blurry, .paused, times: 12)
        feed(.sample, .tracking, times: 2)
        XCTAssertTrue(guide.update(readingNow(.sample)).stateName.hasPrefix("column 1"))
        feed(.blurry, .paused, times: 3)  // 0.3 s
        feed(.sample, .tracking, times: 3)
        XCTAssertTrue(steps.suffix(6).allSatisfy { $0.step.stateName.hasPrefix("column 1") })
        XCTAssertFalse(steps.suffix(6).contains { isEdgeGoBack($0.step.instruction) })
    }

    private func readingNow(_ viewClass: ViewClass) -> GuideReading {
        seconds += 0.1
        return GuideReading(
            seconds: seconds, position: position, tracking: .tracking, unconfirmedGaps: 0,
            viewClass: viewClass, speedFraction: 0.05, isStill: false)
    }

    func testFindSampleDoesNotAskForRefocusOverBlur() {
        feed(.blurry, .paused, times: 20)
        XCTAssertTrue(steps.allSatisfy { $0.step.instruction == .findSample })
    }

    func testBlankGlassOutsideStillFindsEveryEdge() {
        let simulator = GuideSimulator(drop: SimulatedDrop(circles: [(.zero, 3)]), start: .zero)
        let result = simulator.run()
        XCTAssertTrue(result.finished)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95)
        XCTAssertGreaterThan(result.failedProbes, 0)
        XCTAssertTrue(result.states.contains("edge: go back"))
    }

    // MARK: Soil simulations

    private func soilRun(
        _ name: String, _ drop: SimulatedDrop, from start: CGPoint, interior: Int? = nil
    ) -> GuideSimulator.Result {
        let simulator = GuideSimulator(drop: drop, start: start)
        simulator.soil = true
        simulator.interiorFlickerEveryReadings = interior
        let result = simulator.run(maxReadings: 30000)
        print(
            String(
                format: "SOIL %@: readings %d finished %@ captures %d coverage %.1f%% failed probes %d",
                name, result.readings, "\(result.finished)", result.placements.count,
                result.coverage * 100, result.failedProbes))
        XCTAssertTrue(result.finished, name)
        XCTAssertEqual(result.finishReason, .sampleFinished, name)
        XCTAssertGreaterThanOrEqual(result.coverage, 0.95, name)
        XCTAssertFalse(result.instructions.contains(.refocus), "\(name): refocus during travel")
        return result
    }

    func testSoilSquareCoverSlip() {
        _ = soilRun("square 8x8", .square(from: CGPoint(x: -4, y: -4), side: 8), from: .zero)
    }

    func testSoilSquareWithInteriorFlickers() {
        _ = soilRun(
            "square 8x8 + interior", .square(from: CGPoint(x: -4, y: -4), side: 8), from: .zero,
            interior: 60)
    }

    func testSoilRoundDrop() {
        _ = soilRun("round r=3", SimulatedDrop(circles: [(.zero, 3)]), from: .zero)
    }

    func testSoilRoundDropWithInteriorFlickers() {
        _ = soilRun("round r=3 + interior", SimulatedDrop(circles: [(.zero, 3)]), from: .zero, interior: 60)
    }
}
