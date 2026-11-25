import XCTest

@testable import AuraFarm

final class StageManualSwitchTests: XCTestCase {
    private func can(
        _ phase: AutoStageDriver.Phase, autonomous: Bool = true, connected: Bool = true,
        pathRuns: Bool = true, ended: Bool = false, walkingBack: Bool = false,
        summary: Bool = false, calibrating: Bool = false
    ) -> Bool {
        StageManualSwitch.canSwitch(
            phase: phase, isAutonomous: autonomous, isConnected: connected, pathRuns: pathRuns,
            sessionEnded: ended, walkingBack: walkingBack, hasSummary: summary,
            isCalibrating: calibrating)
    }

    func testTheRunningPhasesCanSwitchAndTheOthersCannot() {
        let yes: [AutoStageDriver.Phase] = [
            .following, .presetPath(column: 1, spot: 2), .waitingForEdgeAnswer, .atLimit(.x),
            .crossingEmpty(fields: 1), .emptyCapReached(fields: 2), .paused,
            .returningFromHand(x: 1, y: 2), .checkingFocus,
        ]
        for phase in yes { XCTAssertTrue(can(phase), "\(phase)") }
        let no: [AutoStageDriver.Phase] = [
            .disconnected, .waitingForStageStep, .warmingUp(index: 0, count: 1, title: ""),
            .calibrating(axis: .x, travel: 0), .calibrated(summary: ""), .waitingForFocus,
            .readyToStart, .walkingBack(x: 1, y: 2), .choosingPath, .preparingManual, .byHand,
            .failed("x"),
        ]
        for phase in no { XCTAssertFalse(can(phase), "\(phase)") }
    }

    func testEveryOtherConditionIsNeeded() {
        XCTAssertFalse(can(.following, autonomous: false))
        XCTAssertFalse(can(.following, connected: false))
        XCTAssertFalse(can(.following, pathRuns: false))
        XCTAssertFalse(can(.following, ended: true))
        XCTAssertFalse(can(.following, walkingBack: true))
        XCTAssertFalse(can(.following, summary: true))
        XCTAssertFalse(can(.following, calibrating: true))
    }

    func testARunningPathIsPausedFirstAndAPausedOneIsLeftAlone() {
        XCTAssertTrue(StageManualSwitch.needsPause(.following))
        XCTAssertTrue(StageManualSwitch.needsPause(.checkingFocus))
        XCTAssertFalse(StageManualSwitch.needsPause(.paused))
    }

    func testTheBoardIsAskedAfterHalfASecondAndThenNotCloserThanAThirdOfASecond() {
        let plan = StageManualSwitch()
        XCTAssertEqual(try XCTUnwrap(plan.nextAsk(sinceStop: 0.1, sinceLastAsk: nil)), 0.4, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(plan.nextAsk(sinceStop: 2, sinceLastAsk: nil)), 0)
        XCTAssertEqual(try XCTUnwrap(plan.nextAsk(sinceStop: 2, sinceLastAsk: 0.1)), 0.2, accuracy: 1e-9)
    }

    func testAnIdleAnswerEntersManualAtTheBoardsAngles() {
        var plan = StageManualSwitch()
        XCTAssertNotNil(plan.begin())
        XCTAssertEqual(plan.record(.init(x: 70, y: 110, isIdle: true)), .entered(x: 70, y: 110))
        XCTAssertEqual(plan.state, .idle)
    }

    func testNotIdleThreeTimesOrNoAnswerEndsWithoutManual() {
        for reading: StageManualSwitch.Reading? in [nil, .init(x: 1, y: 2, isIdle: false)] {
            var plan = StageManualSwitch()
            _ = plan.begin()
            XCTAssertNil(plan.record(reading))
            XCTAssertNil(plan.record(reading))
            XCTAssertEqual(plan.record(reading), .didNotAnswer)
            XCTAssertEqual(plan.state, .idle, "back to Auto")
            XCTAssertNil(plan.nextAsk(sinceStop: 9, sinceLastAsk: 9), "the tries are used up")
        }
    }

    func testOnlyThreeAsksAreMade() {
        var plan = StageManualSwitch()
        _ = plan.begin()
        var asks = 0
        while plan.nextAsk(sinceStop: 9, sinceLastAsk: nil) != nil {
            asks += 1
            if plan.record(nil) != nil { break }
        }
        XCTAssertEqual(asks, 3)
    }

    func testACancelledChangeOverEntersNothingAndOnlyOneRunsAtATime() throws {
        var plan = StageManualSwitch()
        let first = try XCTUnwrap(plan.begin())
        XCTAssertNil(plan.begin(), "one change-over at a time")
        plan.cancel()  // a disconnect, or the app in the background
        XCTAssertFalse(plan.isCurrent(first))
        XCTAssertNil(plan.record(.init(x: 1, y: 2, isIdle: true)), "a late answer enters nothing")
        let second = try XCTUnwrap(plan.begin())
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(plan.isCurrent(second))
        plan.cancel()
        plan.cancel()  // twice does nothing
        XCTAssertEqual(plan.state, .idle)
    }

    func testAPositionSavedEarlierStaysTheSavedOne() {
        XCTAssertEqual(StageManualSwitch.saved(existing: (10, 20), reported: (30, 40)).x, 10)
        XCTAssertEqual(StageManualSwitch.saved(existing: (10, 20), reported: (30, 40)).y, 20)
        XCTAssertEqual(StageManualSwitch.saved(existing: nil, reported: (30, 40)).x, 30)
    }
}
