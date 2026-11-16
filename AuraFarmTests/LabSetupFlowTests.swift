import XCTest

@testable import AuraFarm

final class LabSetupFlowTests: XCTestCase {
    func testItStartsAtAlignAndOnlyAlignmentMovesItOn() {
        var flow = LabSetupFlow()
        XCTAssertEqual(flow.step, .align)
        XCTAssertFalse(flow.update(focused: true, fieldConfirmed: true))
        XCTAssertEqual(flow.step, .align)
        XCTAssertTrue(flow.update(alignmentPassed: true))
        XCTAssertEqual(flow.step, .focus)
    }

    func testFocusedMovesFocusOnToFieldAConfirmedFieldToStageAndAMeasuredStageToDone() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true)
        XCTAssertFalse(flow.update(alignmentPassed: true), "align's answer is not focus's")
        XCTAssertEqual(flow.step, .focus)
        flow.update(focused: true)
        XCTAssertEqual(flow.step, .field)
        XCTAssertFalse(flow.update(alignmentPassed: true, focused: true))
        flow.update(fieldConfirmed: true)
        XCTAssertEqual(flow.step, .stage)
        XCTAssertFalse(flow.update(fieldConfirmed: true), "field's answer is not stage's")
        flow.update(stageMeasured: true)
        XCTAssertEqual(flow.step, .done)
        XCTAssertTrue(flow.isDone)
    }

    func testOneStepAtATimeEvenWhenEverythingHolds() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true, focused: true, fieldConfirmed: true)
        XCTAssertEqual(flow.step, .focus)
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

    func testSkippingStartsAtFieldAndSkipGoesStraightToDone() {
        XCTAssertEqual(LabSetupFlow(skippingAlignAndFocus: true).step, .field)
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
        flow.update(focused: true)
        XCTAssertEqual(flow.stepNumber, 3)
        flow.update(fieldConfirmed: true)
        XCTAssertEqual(flow.stepNumber, 4)
        flow.update(stageMeasured: true)
        XCTAssertEqual(flow.stepNumber, 4)
    }

    func testALossInFocusReturnsToFocusAndALossInFieldOrStageReturnsToField() {
        var flow = LabSetupFlow()
        flow.update(alignmentPassed: true)
        flow.alignmentLost()
        XCTAssertEqual(flow.step, .align)
        XCTAssertEqual(flow.resumeStep, .focus)
        XCTAssertTrue(flow.update(alignmentPassed: true))
        XCTAssertEqual(flow.step, .focus)
        XCTAssertNil(flow.resumeStep)

        for step in [LabSetupStep.field, .stage] {
            var flow = LabSetupFlow(skippingAlignAndFocus: true)
            if step == .stage { flow.update(fieldConfirmed: true) }
            XCTAssertEqual(flow.step, step)
            flow.alignmentLost()
            XCTAssertEqual(flow.step, .align)
            flow.update(alignmentPassed: true)
            XCTAssertEqual(flow.step, .field, "from \(step): the mask is learned again")
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
        XCTAssertEqual(flow.step, .focus)
    }
}
