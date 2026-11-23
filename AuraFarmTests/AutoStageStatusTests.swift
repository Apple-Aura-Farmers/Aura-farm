import XCTest

@testable import AuraFarm

final class AutoStageStatusTests: XCTestCase {
    private func status(
        _ phase: AutoStageDriver.Phase, restartNotice: String? = nil, edge: Bool = false,
        client: StageBLEClient.Status = .connected, focusPaused: Bool = false,
        dwelling: Bool = false, hasConnected: Bool = true
    ) -> AutoStageStatus {
        AutoStageStatus.make(
            phase: phase, restartNotice: restartNotice, presetEdgePrompt: edge,
            pathMode: .followGuide, client: client, focusPaused: focusPaused,
            dwelling: dwelling, hasConnected: hasConnected)
    }

    private var everyPhase: [AutoStageDriver.Phase] {
        [
            .disconnected, .waitingForStageStep,
            .warmingUp(index: 2, count: 3, title: "3×3 grid"),
            .calibrating(axis: .x, travel: 0.4), .calibrated(summary: "ok"), .readyToStart,
            .following, .waitingForEdgeAnswer, .atLimit(.y), .walkingBack(x: 40, y: 50),
            .crossingEmpty(fields: 1.2), .emptyCapReached(fields: 2), .presetPath(column: 0, spot: 0),
            .presetPath(column: 3, spot: 2), .paused, .failed("Servo X barely moved"),
        ]
    }

    func testEveryPhaseHasATitle() {
        for phase in everyPhase {
            XCTAssertFalse(status(phase).title.isEmpty, "\(phase)")
        }
    }

    func testARestartNeedsThePerson() {
        let result = status(.paused, restartNotice: "Resume walks it back to 40,50.")
        XCTAssertEqual(result.needsPerson, .stageRestarted)
    }

    func testReadyToStartSaysTheStageIsCalibrated() {
        XCTAssertEqual(status(.readyToStart).title, "Stage calibrated")
        XCTAssertEqual(status(.calibrated(summary: "x")).title, "Stage calibrated")
    }

    func testWarmUpShowsWhichItemOfThree() {
        let result = status(.warmingUp(index: 2, count: 3, title: "3×3 grid"))
        XCTAssertEqual(result.title, "Warming up the stage (2 of 3): 3×3 grid")
    }

    func testEachClientStatusHasItsConnectionText() {
        XCTAssertEqual(
            AutoStageStatus.connectionText(.scanning), "Connecting to the Terraloka Stage…")
        XCTAssertEqual(
            AutoStageStatus.connectionText(.connecting), "Connecting to the Terraloka Stage…")
        XCTAssertEqual(
            AutoStageStatus.connectionText(.reconnecting), "Connecting to the Terraloka Stage…")
        XCTAssertEqual(
            AutoStageStatus.connectionText(.bluetoothUnavailable),
            "Bluetooth is off. Turn it on to use the Terraloka Stage.")
        XCTAssertEqual(
            AutoStageStatus.connectionText(.unauthorized),
            "Bluetooth access is off for Terraloka. Allow it in Settings.")
        XCTAssertEqual(
            AutoStageStatus.connectionText(.idle),
            "Couldn't find the Terraloka Stage. Check it is powered on.")
        XCTAssertFalse(AutoStageStatus.connectionText(.connected).isEmpty)
    }

    func testALinkThatDropsAfterConnectingIsADisconnection() {
        XCTAssertEqual(
            status(.presetPath(column: 2, spot: 1), client: .reconnecting).needsPerson, .disconnected)
        // Before the first connection it is only the connection text.
        let first = status(.disconnected, client: .scanning, hasConnected: false)
        XCTAssertNil(first.needsPerson)
        XCTAssertEqual(first.title, "Connecting to the Terraloka Stage…")
    }

    func testRunningWordsAndTheAlertsThatNeedThePerson() {
        XCTAssertEqual(status(.presetPath(column: 3, spot: 2)).title, "Stage moving · column 3")
        XCTAssertEqual(status(.presetPath(column: 3, spot: 2), dwelling: true).title, "Pausing at a spot")
        XCTAssertEqual(status(.crossingEmpty(fields: 1)).title, "Crossing an empty patch")
        XCTAssertEqual(status(.walkingBack(x: 1, y: 2)).title, "Walking the stage back")
        XCTAssertEqual(status(.paused).title, "Paused")
        XCTAssertEqual(status(.following, focusPaused: true).needsPerson, .focusPause)
        XCTAssertEqual(status(.emptyCapReached(fields: 2)).needsPerson, .emptyCapReached)
        XCTAssertEqual(status(.failed("why")).needsPerson, .calibrationFailed("why"))
        XCTAssertNil(status(.following).needsPerson)
    }

    func testTheRecommendedCoverageFollowsTheObjective() {
        XCTAssertEqual(GuidedScanCoverage.recommended(for: .x100), .everySecondColumn)
        XCTAssertEqual(GuidedScanCoverage.recommended(for: .x40), .everyColumn)
    }

    func testTheDefaultWarmUpIsTraverseThenTheGridThenTheCross() {
        let items = StageWarmUpItem.defaultSequence
        XCTAssertEqual(items, [.traverse, .preset(.grid3x3), .preset(.centreCross)])
        XCTAssertEqual(items.map(\.title), ["Traverse", "3×3 grid", "Centre cross"])
    }

    func testTheStageStepIsCalledStageCalibrationForTheTerralokaStage() {
        XCTAssertEqual(
            GuidedScanSetupStage.stage.indicator(automatedStage: true),
            "Step 4 of 4: Stage calibration")
        XCTAssertEqual(
            GuidedScanSetupStage.stage.indicator(automatedStage: false),
            GuidedScanSetupStage.stage.indicator)
    }
}
