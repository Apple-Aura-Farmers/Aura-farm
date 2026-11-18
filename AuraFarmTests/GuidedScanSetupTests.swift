import XCTest

@testable import AuraFarm

final class GuidedScanSetupTests: XCTestCase {
    private func stage(_ flow: LabSetupFlow) -> GuidedScanSetupStage { .current(step: flow.step) }

    func testThereIsNoStageBeforeTheLabsFirstStep() {
        XCTAssertEqual(GuidedScanSetupStage.allCases, [.align, .field, .focus, .stage, .ready])
        XCTAssertEqual(GuidedScanSetupStage.stepCount, LabSetupFlow.stepCount)
    }

    func testThePageFollowsLabSetupFlowExactly() {
        var flow = LabSetupFlow()
        var shown = [stage(flow)]
        let moves: [(inout LabSetupFlow) -> Void] = [
            { $0.update(alignmentPassed: true) }, { $0.update(fieldConfirmed: true) },
            { $0.update(focused: true) }, { $0.update(stageMeasured: true) },
        ]
        for move in moves {
            move(&flow)
            shown.append(stage(flow))
        }
        XCTAssertEqual(shown, [.align, .field, .focus, .stage, .ready])
        XCTAssertEqual(shown.dropLast().compactMap(\.number), [1, 2, 3, 4])
        XCTAssertEqual(shown.map { $0.number ?? 0 }.dropLast(), [1, 2, 3, 4])
        XCTAssertEqual(GuidedScanSetupStage.align.indicator, "Step 1 of 4: Align")
        XCTAssertEqual(GuidedScanSetupStage.field.indicator, "Step 2 of 4: Find the eyepiece")
        XCTAssertEqual(GuidedScanSetupStage.focus.indicator, "Step 3 of 4: Focus")
        XCTAssertEqual(GuidedScanSetupStage.ready.indicator, "Ready")
    }

    func testRedoSetupAndTheStageSkipAndTheSkipSettingFollowTheLab() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true)
        flow.update(fieldConfirmed: true)
        flow.update(focused: true)
        XCTAssertEqual(stage(flow), .stage)
        flow.skip()  // the stage step's Skip goes straight to the end of setup
        XCTAssertEqual(stage(flow), .ready)
        flow.redo()
        XCTAssertEqual(stage(flow), .align)
        flow.redoField()
        XCTAssertEqual(stage(flow), .field)
        XCTAssertEqual(stage(LabSetupFlow(skippingAlignAndFocus: true)), .field)
        // The lab's own session is what the page runs.
        XCTAssertEqual(LabSetupSession(skippingAlignAndFocus: true).step, .field)
    }

    func testAlignShowsTheWholePictureWithNoCircleNoCropAndNoDarkening() {
        for stage in [GuidedScanSetupStage.align, .focus, .field] {
            let look = stage.treatment
            XCTAssertFalse(look.centres, "\(stage) is not cropped before the field is confirmed")
            XCTAssertFalse(look.darkensOutside)
            XCTAssertFalse(look.drawsTargetOutline)
        }
        XCTAssertTrue(GuidedScanSetupStage.stage.treatment.centres, "from the lab's stage step")
        XCTAssertTrue(GuidedScanSetupStage.ready.treatment.centres)
        XCTAssertFalse(GuidedScanSetupStage.allCases.contains { $0.treatment.drawsTargetOutline })
    }

    func testTheTicksAreTheLabsAlignmentReadingInFourLines() {
        var reading = AlignmentReading()
        reading.found = true
        reading.problems = [.clipped, .glare]
        let ticks = AlignmentTicks(reading: reading, passed: false)
        XCTAssertEqual(ticks.lines.map(\.isOK), [false, true, true, false])
        XCTAssertEqual(
            ticks.lines.map(\.text), ["Whole circle in view", "Round", "Evenly lit", "No glare"])
        // No circle at all: nothing is ticked.
        XCTAssertEqual(
            AlignmentTicks(reading: AlignmentReading(), passed: false).lines.map(\.isOK),
            [false, false, false, false])
        let good = AlignmentTicks(reading: AlignmentReading(found: true), passed: true)
        XCTAssertTrue(good.lines.allSatisfy(\.isOK))
        XCTAssertTrue(good.passed)
    }

    func testTheWordsAreThePlainSentencesOfTheBrief() {
        XCTAssertEqual(
            GuidedScanSetupStage.align.sentence,
            "Move the phone until the whole round view is inside the picture, round and evenly lit.")
        XCTAssertEqual(
            GuidedScanSetupStage.focus.sentence,
            "Turn the microscope's focus knob slowly until the picture is sharp.")
    }

    #if DEBUG
        /// The page's settings are the lab's own; only three differ.
        func testThePageOverridesOnlyTheGuideTheCoverageAndTheDetections() {
            var lab = LabSettings()
            lab.mappingName = ScreenMapping.rotateLeft.rawValue
            lab.skipsAlignFocus = true
            lab.confidence = 0.4
            lab.showsDetections = true
            lab.coverageStep = 2.4
            let page = lab.forGuidedScan(coverage: 1.6)

            var expected = lab
            expected.guideDryRun = true
            expected.coverageStep = 1.6
            expected.showsDetections = false
            XCTAssertEqual(page, expected)
            XCTAssertTrue(page.guideDryRun)
            XCTAssertEqual(page.mappingName, lab.mappingName)
            XCTAssertEqual(page.skipsAlignFocus, true)
        }

        func testTheLabsDefaultsAreTheOnesTheLabViewHadAtHead() {
            let lab = LabSettings()
            XCTAssertEqual(lab.mappingName, "rotateRight")
            XCTAssertEqual(lab.coverageStep, 0.8)
            XCTAssertEqual(lab.spotMode, .briefTouch)
            XCTAssertEqual(lab.detectorModelName, DetectorModel.v2.rawValue)
            XCTAssertEqual(lab.cameraRateName, CameraRate.fps20.rawValue)
            XCTAssertFalse(lab.guideDryRun)
        }
    #endif

    func testTheGuidedScanLocksTheSheetsDismissalWhileOpenAndOnlyThen() {
        var launch = GuidedScanLaunch()
        XCTAssertFalse(launch.locksSheetDismissal, "before it opens")
        launch.open()
        XCTAssertTrue(launch.isOpen)
        XCTAssertTrue(launch.locksSheetDismissal, "while it is open, setup included")
        launch.close()
        XCTAssertFalse(launch.locksSheetDismissal, "after it closes")
    }
}
