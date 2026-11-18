import XCTest

@testable import AuraFarm

final class LabSetupFlowTests: XCTestCase {
    func testItStartsAtAlignAndOnlyAlignmentMovesItOn() {
        var flow = LabSetupFlow()
        XCTAssertEqual(flow.step, .align)
        XCTAssertFalse(flow.update(focused: true, fieldConfirmed: true))
        XCTAssertEqual(flow.step, .align)
        XCTAssertTrue(flow.update(alignmentPassed: true))
        XCTAssertEqual(flow.step, .field, "the eyepiece is found before focusing")
    }

    func testAConfirmedFieldMovesOnToFocusFocusToStageAndAMeasuredStageToDone() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true)
        XCTAssertFalse(flow.update(alignmentPassed: true), "align's answer is not field's")
        XCTAssertFalse(flow.update(focused: true), "focus cannot come before the field")
        XCTAssertEqual(flow.step, .field)
        flow.update(fieldConfirmed: true)
        XCTAssertEqual(flow.step, .focus)
        XCTAssertFalse(flow.update(alignmentPassed: true, fieldConfirmed: true))
        flow.update(focused: true)
        XCTAssertEqual(flow.step, .stage)
        XCTAssertFalse(flow.update(focused: true), "focus's answer is not stage's")
        flow.update(stageMeasured: true)
        XCTAssertEqual(flow.step, .done)
        XCTAssertTrue(flow.isDone)
    }

    func testOneStepAtATimeEvenWhenEverythingHolds() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true, focused: true, fieldConfirmed: true)
        XCTAssertEqual(flow.step, .field)
    }

    func testRedoGoesBackToAlignAndRedoFieldToField() {
        var flow = LabSetupFlow()
        flow.skip()
        XCTAssertEqual(flow.step, .done)
        flow.redoField()
        XCTAssertEqual(flow.step, .field)
        flow.redo()
        XCTAssertEqual(flow.step, .align)
    }

    func testSkippingAlignAndFocusStartsAtFieldAndSkipsFocusButNotTheField() {
        var skipping = LabSetupFlow(skippingAlignAndFocus: true)
        XCTAssertEqual(skipping.step, .field)
        skipping.update(fieldConfirmed: true)
        XCTAssertEqual(skipping.step, .stage, "the field step ran; focus is skipped")
        // Redo is all of it again, focus included.
        skipping.redo()
        skipping.update(alignmentPassed: true)
        skipping.update(fieldConfirmed: true)
        XCTAssertEqual(skipping.step, .focus)

        var flow = LabSetupFlow()
        flow.skip()
        XCTAssertEqual(flow.step, .done)
    }

    func testStepNumberAndCountForTheIndicator() {
        var flow = LabSetupFlow()
        XCTAssertEqual(LabSetupFlow.stepCount, 4)
        XCTAssertEqual(flow.stepNumber, 1)
        flow.update(alignmentPassed: true)
        XCTAssertEqual(flow.stepNumber, 2)
        flow.update(fieldConfirmed: true)
        XCTAssertEqual(flow.stepNumber, 3)
        flow.update(focused: true)
        XCTAssertEqual(flow.stepNumber, 4)
        flow.update(stageMeasured: true)
        XCTAssertEqual(flow.stepNumber, 4)
    }

    func testALossInFieldFocusOrStageReturnsToFieldAndFocusFollows() {
        for lostAt in [LabSetupStep.field, .focus, .stage] {
            var flow = LabSetupFlow()
            flow.update(alignmentPassed: true)
            if lostAt != .field { flow.update(fieldConfirmed: true) }
            if lostAt == .stage { flow.update(focused: true) }
            XCTAssertEqual(flow.step, lostAt)
            flow.alignmentLost()
            XCTAssertEqual(flow.step, .align)
            XCTAssertEqual(flow.resumeStep, .field, "from \(lostAt): the circle moved")
            XCTAssertTrue(flow.update(alignmentPassed: true))
            XCTAssertEqual(flow.step, .field, "from \(lostAt): the mask is learned again")
            XCTAssertNil(flow.resumeStep)
            flow.update(fieldConfirmed: true)
            XCTAssertEqual(flow.step, .focus, "from \(lostAt): focus comes round again")
        }
    }

    func testALossAtAlignOrWhenDoneChangesNothingAndRedoForgetsTheResume() {
        var flow = LabSetupFlow()
        flow.alignmentLost()
        XCTAssertNil(flow.resumeStep)
        flow.skip()
        flow.alignmentLost()
        XCTAssertEqual(flow.step, .done)
        flow.redoField()
        flow.alignmentLost()
        flow.redo()
        XCTAssertNil(flow.resumeStep)
        flow.update(alignmentPassed: true)
        XCTAssertEqual(flow.step, .field)
    }
}
