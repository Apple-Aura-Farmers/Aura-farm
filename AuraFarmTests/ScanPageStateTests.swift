import XCTest

@testable import AuraFarm

/// The Scan page's status, card, title and ring, drawn from plain values.
final class ScanPageStateTests: XCTestCase {
    private func stage(
        _ phase: AutoStageDriver.Phase, _ change: (inout ScanStageInput) -> Void = { _ in }
    ) -> ScanStageInput {
        var s = ScanStageInput()
        s.phase = phase
        s.connectionText = "Connecting to the Terraloka Stage…"
        change(&s)
        return s
    }

    private func status(
        _ phase: AutoStageDriver.Phase, _ change: (inout ScanStageInput) -> Void = { _ in }
    ) -> ScanStatus {
        ScanStatusMaker.make(stage(phase, change))
    }

    private let rows = [ScanFoundRow(name: "Ciliates", count: 4)]

    // MARK: Status

    func testTheSteadyMovingStatusIsTheSameWhenItMovesAndWhenItDwells() {
        // The dwell is not an input at all, so the words cannot flicker between the two.
        XCTAssertEqual(
            status(.presetPath(column: 7, spot: 7)),
            ScanStatus(title: "Stage Moving • Column 7", detail: "Spot 7"))
        XCTAssertEqual(status(.presetPath(column: 0, spot: 0)), ScanStatus(title: "Moving to Start"))
    }

    func testFollowingAndItsSubStates() {
        XCTAssertEqual(status(.following) { $0.column = 3 }.title, "Stage Moving • Column 3")
        XCTAssertEqual(status(.following).title, "Stage Moving")
        XCTAssertEqual(status(.crossingEmpty(fields: 1)).title, "Crossing an Empty Patch")
        XCTAssertEqual(status(.atLimit(.x)).title, "End of Range")
    }

    func testThePlainPhases() {
        XCTAssertEqual(status(.paused).title, "Paused")
        XCTAssertEqual(status(.paused) { $0.isSwitchingToManual = true }.title, "Switching to Manual")
        XCTAssertEqual(status(.byHand), ScanStatus(title: "Manual", detail: "Not counted"))
        XCTAssertEqual(status(.returningFromHand(x: 1, y: 2)).title, "Going Back")
        XCTAssertEqual(
            status(.checkingFocus), ScanStatus(title: "Going Back", detail: "Checking focus"))
        XCTAssertEqual(status(.following) { $0.isComplete = true }.title, "Detection Complete")
    }

    func testEveryAlertHasItsWordsInOrange() {
        let restarted = status(.paused) { $0.alert = .stageRestarted }
        XCTAssertEqual(restarted.title, "Stage Restarted")
        XCTAssertEqual(restarted.detail, "Check its power, then tap Resume.")
        let disconnected = status(.following) { $0.alert = .disconnected }
        XCTAssertEqual(disconnected.title, "Stage Disconnected")
        XCTAssertEqual(disconnected.detail, "Connecting to the Terraloka Stage…")
        let empty = status(.emptyCapReached(fields: 2)) { $0.alert = .emptyCapReached }
        XCTAssertEqual(empty.title, "No Sample Found")
        XCTAssertEqual(empty.detail, "Keep going or end this column?")
        let hot = status(.presetPath(column: 2, spot: 1)) { $0.isTooHot = true }
        XCTAssertEqual(hot.title, "Phone Too Hot")
        XCTAssertEqual(hot.detail, "The stage waits and carries on by itself.")
        let moved = status(.presetPath(column: 2, spot: 1)) { $0.alignmentPaused = true }
        XCTAssertEqual(moved.title, "Phone Moved")
        XCTAssertEqual(moved.detail, HelperInstruction.phoneMoved.text)
        for warning in [restarted, disconnected, empty, hot, moved] { XCTAssertTrue(warning.isWarning) }
        XCTAssertFalse(status(.paused).isWarning)
    }

    func testTheFocusPauseSaysTheHintThenTheDialThenTheDefault() {
        let dial = FocusDialReading(
            offset: -0.5, side: .approaching, greenHalfWidth: 0.2, isGreen: false,
            isWrongWay: false, message: "Dial words")
        let both = status(.presetPath(column: 1, spot: 1)) {
            $0.alert = .focusPause
            $0.focusHint = "Hint words"
            $0.dial = dial
        }
        XCTAssertEqual(both, ScanStatus(title: "Focusing Issue", detail: "Hint words", isWarning: true))
        let dialOnly = status(.presetPath(column: 1, spot: 1)) {
            $0.alert = .focusPause
            $0.dial = dial
        }
        XCTAssertEqual(dialOnly.detail, "Dial words")
        let neither = status(.presetPath(column: 1, spot: 1)) { $0.alert = .focusPause }
        XCTAssertEqual(neither.detail, "Check your focus and make sure it's clear.")
    }

    func testManualReminderNoteAndAFailedSwitch() {
        let reminder = status(.byHand) { $0.handFocusReminder = true }
        XCTAssertEqual(reminder.title, "Check Focus")
        XCTAssertEqual(reminder.detail, "Not counted")
        XCTAssertTrue(reminder.isWarning && reminder.isReminder)
        let note = status(.byHand) { $0.handNote = "At the end of the range." }
        XCTAssertEqual(note, ScanStatus(title: "Manual", detail: "At the end of the range."))
        let failed = status(.paused) { $0.manualSwitchProblem = "The stage did not answer." }
        XCTAssertEqual(
            failed,
            ScanStatus(title: "Paused", detail: "The stage did not answer.", isWarning: true))
    }

    func testAWarningClearsWhenItsCauseDoes() {
        var s = stage(.presetPath(column: 2, spot: 1)) { $0.alert = .focusPause }
        XCTAssertTrue(ScanStatusMaker.make(s).isWarning)
        s.alert = nil
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Stage Moving • Column 2")
    }

    func testThePrecedence() {
        // The stage's alerts first, then too hot, then alignment, then the rest.
        var s = stage(.presetPath(column: 2, spot: 1)) {
            $0.alert = .disconnected
            $0.isTooHot = true
            $0.alignmentPaused = true
            $0.isSwitchingToManual = true
        }
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Stage Disconnected")
        s.alert = nil
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Phone Too Hot")
        s.isTooHot = false
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Phone Moved")
        s.alignmentPaused = false
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Switching to Manual")
        s.isSwitchingToManual = false
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Stage Moving • Column 2")
        s.alert = .stageRestarted
        s.isComplete = true
        XCTAssertEqual(ScanStatusMaker.make(s).title, "Detection Complete")
    }

    func testEveryPhaseHasAStatus() {
        let phases: [AutoStageDriver.Phase] = [
            .disconnected, .waitingForStageStep, .waitingForFocus, .readyToStart, .following,
            .waitingForEdgeAnswer, .atLimit(.y), .walkingBack(x: 1, y: 2),
            .crossingEmpty(fields: 1), .emptyCapReached(fields: 2), .presetPath(column: 0, spot: 0),
            .presetPath(column: 3, spot: 2), .paused, .choosingPath, .preparingManual, .byHand,
            .returningFromHand(x: 1, y: 2), .checkingFocus, .failed("x"),
        ]
        for phase in phases {
            var s = stage(phase)
            s.fallback = AutoStageStatus(title: "fallback")
            XCTAssertFalse(ScanStatusMaker.make(s).title.isEmpty, "\(phase)")
        }
    }

    // MARK: Card

    func testTheCardForEachAlertAndPhase() {
        let found = ScanCard.found(rows)
        XCTAssertEqual(ScanCardMaker.make(stage(.following), found: rows), found)
        XCTAssertEqual(ScanCardMaker.make(stage(.byHand), found: rows), .manualPad)
        // The pad wins over an alert, as it did.
        XCTAssertEqual(
            ScanCardMaker.make(stage(.byHand) { $0.alert = .disconnected }, found: rows), .manualPad)
        let focus = stage(.following) {
            $0.alert = .focusPause
            $0.canConfirmEmptyArea = true
        }
        XCTAssertEqual(
            ScanCardMaker.make(focus, found: rows), .focus(dial: nil, canConfirmEmptyArea: true))
        let other = stage(.paused) {
            $0.alert = .stageRestarted
            $0.alertButtons = ["Resume"]
        }
        XCTAssertEqual(ScanCardMaker.make(other, found: rows), .alert(buttons: ["Resume"]))
        // Too hot and an alignment pause have no buttons: the found list stays.
        XCTAssertEqual(ScanCardMaker.make(stage(.following) { $0.isTooHot = true }, found: rows), found)
    }

    func testTheFocusCardGivesWayToTheFoundListWhenFocusIsRestored() {
        var s = stage(.presetPath(column: 1, spot: 1)) { $0.alert = .focusPause }
        if case .focus = ScanCardMaker.make(s, found: rows) {} else { XCTFail("focus card") }
        s.alert = nil
        XCTAssertEqual(ScanCardMaker.make(s, found: rows), .found(rows))
    }

    func testFoundRowsAreFlattenedAndSortedMostFirst() {
        let found = ScanFound.rows([
            "amoeba": 3, "paramecium": 6, "stentor": 4, "nematode": 3, "euglena": 3, "volvox": 0,
        ])
        // Ciliates 10, then the 3s by name: Amoebae, Euglenoids, Nematodes. Zero counts are left out.
        XCTAssertEqual(
            found,
            [
                ScanFoundRow(name: "Ciliates", count: 10), ScanFoundRow(name: "Amoebae", count: 3),
                ScanFoundRow(name: "Euglenoids", count: 3), ScanFoundRow(name: "Nematodes", count: 3),
            ])
        XCTAssertEqual(ScanFound.rows([:]), [])
    }

    // MARK: Title, ring, boxes

    func testTheTitle() {
        XCTAssertEqual(
            ScanTitle.make(sampleID: "Pak Wayan", plotName: "Plot 1", isOwnSample: false),
            "Pak Wayan • Plot 1")
        XCTAssertEqual(
            ScanTitle.make(sampleID: "My soil", plotName: "Plot 1", isOwnSample: true), "My soil")
        // A plot that repeats the name shows once, with or without its farmer in front.
        XCTAssertEqual(
            ScanTitle.make(sampleID: "Pak Wayan", plotName: "Pak Wayan", isOwnSample: false),
            "Pak Wayan")
        XCTAssertEqual(
            ScanTitle.make(sampleID: "Pak Wayan", plotName: "Pak Wayan, Plot 1", isOwnSample: false),
            "Pak Wayan • Plot 1")
        XCTAssertEqual(
            ScanTitle.make(sampleID: "Pak Wayan", plotName: nil, isOwnSample: false), "Pak Wayan")
    }

    func testTheRingIsEmptyInManualAndNotOtherwise() {
        var i = ScanPageInput()
        i.fraction = 0.4
        i.stage = stage(.byHand)
        XCTAssertTrue(ScanPageState.make(i).ringIsEmpty)
        XCTAssertEqual(ScanPageState.make(i).mode, .manual)
        i.stage = stage(.following)
        XCTAssertFalse(ScanPageState.make(i).ringIsEmpty)
        i.stage = stage(.paused) { $0.isSwitchingToManual = true }
        XCTAssertTrue(ScanPageState.make(i).ringIsEmpty)
        // Going back and checking focus are Auto.
        i.stage = stage(.checkingFocus)
        XCTAssertEqual(ScanPageState.make(i).mode, .auto)
    }

    func testPauseIsHiddenInManualAndGoesBackWhenASavedPositionWaits() {
        var i = ScanPageInput()
        i.stage = stage(.byHand)
        XCTAssertNil(ScanPageState.make(i).top.pause)
        i.stage = stage(.paused)
        i.isPaused = true
        XCTAssertEqual(ScanPageState.make(i).top.pause, .resume)
        i.goesBackFirst = true
        XCTAssertEqual(ScanPageState.make(i).top.pause, .goBackAndResume)
        i.isPaused = false
        XCTAssertEqual(ScanPageState.make(i).top.pause, .pause)
        i.endingAfterColumn = true
        XCTAssertEqual(ScanPageState.make(i).top.endLabel, "Ending…")
    }

    func testTheLadybugHidesBoxesInARunsManualButNotInTheLookOnlySession() {
        // A run: the ladybug decides, steering or not.
        XCTAssertFalse(ScanBoxes.shown(showsDetections: false, hasStarted: true, handHoldOn: true))
        XCTAssertTrue(ScanBoxes.shown(showsDetections: true, hasStarted: true, handHoldOn: true))
        // The look-only session before a run always shows what it sees while steering.
        XCTAssertTrue(ScanBoxes.shown(showsDetections: false, hasStarted: false, handHoldOn: true))
        XCTAssertFalse(ScanBoxes.shown(showsDetections: false, hasStarted: false, handHoldOn: false))
    }

    #if DEBUG
        // MARK: Debug state picker

        func testEveryDebugStateBuildsAValue() {
            for scenario in ScanScenario.allCases {
                for kinds in [0, 3, 12] {
                    var options = ScanPreviewOptions()
                    options.kindCount = kinds
                    let state = ScanPageState.make(scenario.input(options))
                    XCTAssertFalse(state.status.title.isEmpty, scenario.title)
                    XCTAssertFalse(state.top.title.isEmpty, scenario.title)
                }
            }
        }

        func testDebugStatesShowTheirWords() {
            let o = ScanPreviewOptions()
            func state(_ s: ScanScenario) -> ScanPageState { .make(s.input(o)) }
            XCTAssertEqual(state(.movingToStart).status.title, "Moving to Start")
            XCTAssertEqual(state(.focusNoDial).card, .focus(dial: nil, canConfirmEmptyArea: false))
            XCTAssertEqual(state(.manual).card, .manualPad)
            XCTAssertEqual(state(.manualCheckFocus).status.title, "Check Focus")
            XCTAssertEqual(state(.complete).status.title, "Detection Complete")
            XCTAssertTrue(state(.loading).showsLoading)
            XCTAssertEqual(state(.movingNone).card, .found([]))
            XCTAssertEqual(state(.pausedGoesBack).top.pause, .goBackAndResume)
            XCTAssertEqual(state(.endingAfterColumn).top.endLabel, "Ending…")
        }

        @MainActor
        func testDebugActionsOnlyChangeTheFakeStateAndClosingCallsNothingElse() {
            var closed = 0
            let model = ScanPreviewModel(onClose: { closed += 1 })
            let actions = model.actions
            actions.togglePause()
            XCTAssertEqual(model.scenario, .paused)
            actions.togglePause()
            XCTAssertEqual(model.scenario, .movingWithOrganisms)
            actions.setMode(.manual)
            XCTAssertEqual(model.scenario, .manual)
            let before = model.options.y
            actions.press(.up)
            XCTAssertEqual(model.options.y, before + 3)
            actions.release(.up)
            actions.setMode(.auto)
            XCTAssertEqual(model.scenario, .movingWithOrganisms)
            actions.toggleBoxes()
            XCTAssertFalse(model.options.boxesOn)
            actions.chooseEnd(.endAfterColumn)
            XCTAssertEqual(model.scenario, .endingAfterColumn)
            for nothing in [actions.dismissReminder, actions.openPadSettings] { nothing() }
            actions.alertAction("Retry")
            actions.chooseEnd(.keepScanning)
            XCTAssertEqual(closed, 0)
            // End now and Stop and discard close the page without saving: the only way out.
            actions.chooseEnd(.endNow)
            actions.chooseEnd(.discard)
            actions.close()
            XCTAssertEqual(closed, 3)
        }
    #endif
}
