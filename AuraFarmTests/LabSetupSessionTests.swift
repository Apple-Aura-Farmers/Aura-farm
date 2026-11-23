import SwiftUI
import XCTest

@testable import AuraFarm

final class LabSetupSessionTests: XCTestCase {
    private let size = CGSize(width: 1280, height: 720)

    /// A bright disc on a dark frame, like the microscope's field.
    private func discFrame() -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 640, Double(y) - 360) <= 300 ? 200 : 10
        }
    }

    private func makePipeline() -> SlideMovementPipeline {
        let pipeline = SlideMovementPipeline()
        pipeline.requiresReview = true
        return pipeline
    }

    private func progress(_ pipeline: SlideMovementPipeline) -> Double {
        if case .learning(let progress) = pipeline.fieldState { return progress }
        return 1
    }

    private func isSetup(_ output: LabSetupSession.Output?) -> Bool {
        if case .setup? = output { return true }
        return false
    }

    private func isTracked(_ output: LabSetupSession.Output?) -> Bool {
        if case .tracked? = output { return true }
        return false
    }

    func testAlignDoesNotLearnThenFieldLearnsThenFocusDoesNotTrack() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        let frame = discFrame()
        var seconds = 0.0
        func feed(_ count: Int) -> [LabSetupSession.Output?] {
            (0..<count).map { _ in
                seconds += 0.1
                return session.process(
                    frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
            }
        }

        // Align: 1.5 s of a whole, round, even disc passes it; nothing learns yet.
        let align = feed(14)
        XCTAssertEqual(session.step, .align)
        XCTAssertTrue(align.allSatisfy(isSetup), "no frame went to the pipeline")
        XCTAssertEqual(progress(pipeline), 0, "no mask learning in align")
        _ = feed(4)
        XCTAssertEqual(session.step, .field, "the eyepiece is found next")
        XCTAssertTrue(session.info.isAlignmentPassed)

        // Field: the frames go to the pipeline, which learns, and waits for the review.
        let field = feed(31)
        XCTAssertTrue(field.allSatisfy(isTracked))
        XCTAssertTrue(pipeline.isAwaitingReview)
        XCTAssertEqual(session.step, .field)
        pipeline.confirmField()
        _ = feed(1)
        XCTAssertEqual(session.step, .focus)

        // Focus: a flat disc has no sharpness peak, so it stays here; frames do not track.
        let focus = feed(30)
        XCTAssertEqual(session.step, .focus)
        XCTAssertTrue(focus.allSatisfy(isSetup))
        XCTAssertNotNil(session.info.focusSquare)
        XCTAssertNotNil(session.info.focus)
        XCTAssertFalse(session.log.isEmpty)
        XCTAssertTrue(session.log.contains { $0.step == .focus && $0.focus != nil })
    }

    func testFocusIsMeasuredInsideTheConfirmedRoundView() throws {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: false)
        let time = reachFocus(session: session, pipeline: pipeline)
        feed(discFrame(), for: 0.5, from: time, session: session, pipeline: pipeline)
        let mask = try XCTUnwrap(pipeline.fieldState.mask)
        let circle = try XCTUnwrap(FieldCircle(fitting: mask))
        let expected = LabSetupSession.focusSquare(for: circle, frameSize: size)
        XCTAssertEqual(session.info.focusSquare, expected)
    }

    func testAlignWaitsForAConfirmWhenTheSessionAsksForOne() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        session.confirmsSteps = true
        var time = feed(discFrame(), for: 4.0, from: 0, session: session, pipeline: pipeline)
        XCTAssertTrue(session.info.isAlignmentPassed, "the checks passed")
        XCTAssertEqual(session.step, .align, "but it waits for the person")
        session.confirmStep()
        time = feed(discFrame(), for: 0.3, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .field)
        // Without the setting (the lab) the step moves on by itself, as before.
        let lab = LabSetupSession()
        feed(discFrame(), for: 2.0, from: 0, session: lab, pipeline: makePipeline())
        XCTAssertEqual(lab.step, .field)
    }

    func testFocusWaitsForAConfirmAndThenSetsTheBaseline() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = reachFocus(session: session, pipeline: pipeline)
        session.confirmsSteps = true
        for amplitude in [30.0, 60, 80, 80, 80, 20, 20, 20, 80, 80] {
            time = feed(
                texturedFrame(amplitude), for: 0.4, from: time, session: session, pipeline: pipeline)
        }
        time = feed(texturedFrame(80), for: 3, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.info.focus?.state, .focused)
        XCTAssertEqual(session.step, .focus, "focused, but waiting for the person")
        XCTAssertNil(session.focusBaseline)
        XCTAssertFalse(session.info.focusFound)
        session.confirmStep()
        feed(texturedFrame(80), for: 0.3, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .stage)
        XCTAssertNotNil(session.focusBaseline)
        XCTAssertTrue(session.info.focusFound)
        session.redo()
        XCTAssertFalse(session.info.focusFound, "asked for again after a redo")
    }

    /// The panel must not stay up over a picture that was turned out of focus again.
    func testAFoundFocusThatFadesBeforeItIsConfirmedIsLostAndCanBeFoundAgain() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = reachFocus(session: session, pipeline: pipeline)
        session.confirmsSteps = true
        func sweep() {
            for amplitude in [30.0, 60, 80, 80, 80, 20, 20, 20, 80, 80] {
                time = feed(
                    texturedFrame(amplitude), for: 0.4, from: time, session: session,
                    pipeline: pipeline)
            }
            time = feed(texturedFrame(80), for: 3, from: time, session: session, pipeline: pipeline)
        }
        sweep()
        XCTAssertEqual(session.info.focus?.state, .focused)
        time = feed(texturedFrame(20), for: 0.5, from: time, session: session, pipeline: pipeline)
        session.confirmStep()
        time = feed(texturedFrame(20), for: 0.2, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus, "a tap on a blurry picture does not move on")
        time = feed(texturedFrame(20), for: 1.5, from: time, session: session, pipeline: pipeline)
        XCTAssertNotEqual(session.info.focus?.state, .focused)
        sweep()
        XCTAssertEqual(session.info.focus?.state, .focused, "found again")
        XCTAssertEqual(session.step, .focus, "the early tap was forgotten")
        session.confirmStep()
        feed(texturedFrame(80), for: 0.3, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .stage)
    }

    func testFocusIsNotFoundWhenItWasSkipped() {
        let skipping = LabSetupSession(skippingAlignAndFocus: true)
        let pipeline = makePipeline()
        var time = feed(discFrame(), for: 1.0, from: 0, session: skipping, pipeline: pipeline)
        for _ in 0..<40 where pipeline.fieldState.mask == nil {
            time = feed(discFrame(), for: 0.2, from: time, session: skipping, pipeline: pipeline)
        }
        pipeline.confirmField()
        feed(discFrame(), for: 0.5, from: time, session: skipping, pipeline: pipeline)
        XCTAssertEqual(skipping.step, .stage)
        XCTAssertFalse(skipping.info.focusFound)

        let session = LabSetupSession()
        session.skipEverything()
        XCTAssertEqual(session.step, .done)
        XCTAssertFalse(session.info.focusFound)
    }

    func testFocusFinishingSetsTheBaselineAndMovesOnToTheStage() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = reachFocus(session: session, pipeline: pipeline)
        XCTAssertNil(session.focusBaseline)
        // The knob goes to a sharp picture, past it, and back to it, then holds.
        for amplitude in [30.0, 60, 80, 80, 80, 20, 20, 20, 80, 80] {
            time = feed(texturedFrame(amplitude), for: 0.4, from: time, session: session, pipeline: pipeline)
        }
        time = feed(texturedFrame(80), for: 3, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .stage, "focused, so on to the knobs")
        XCTAssertNotNil(session.focusBaseline, "the run monitor's baseline is set")
    }

    /// A bright disc with a fine texture of the given strength: sharper when stronger.
    private func texturedFrame(_ amplitude: Double) -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { x, y in
            guard hypot(Double(x) - 640, Double(y) - 360) <= 300 else { return 10 }
            let wave = sin(Double(x) * 0.5) * sin(Double(y) * 0.5)
            return UInt8(max(0, min(255, 170 + amplitude * wave)))
        }
    }

    /// Feeds a whole disc through align and the field step (confirmed), to the start of focus.
    private func reachFocus(session: LabSetupSession, pipeline: SlideMovementPipeline) -> Double {
        var time = feed(discFrame(), for: 2.0, from: 0, session: session, pipeline: pipeline)
        time = feed(discFrame(), for: 3.2, from: time, session: session, pipeline: pipeline)
        pipeline.confirmField()
        time = feed(discFrame(), for: 0.2, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        return time
    }

    func testFieldConfirmedMovesOnToStageAndSkippingTheStageUsesTheIdentity() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        XCTAssertEqual(session.step, .field)
        let frame = discFrame()
        var seconds = 0.0
        for _ in 0..<31 {
            seconds += 0.1
            XCTAssertTrue(
                isTracked(
                    session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)))
        }
        XCTAssertTrue(pipeline.isAwaitingReview)
        XCTAssertEqual(session.step, .field, "waiting for the person to confirm")
        pipeline.confirmField()
        seconds += 0.1
        _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        XCTAssertEqual(session.step, .stage)
        XCTAssertNil(session.stageAxes)
        session.skipStage()
        XCTAssertEqual(session.step, .done)
        XCTAssertEqual(session.stageAxes, .identity)
        XCTAssertEqual(session.info.stageAxes, .identity)
    }

    func testCompleteStageAtTheStageStepMovesToDoneWithThoseAxes() throws {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        let frame = discFrame()
        var seconds = 0.0
        for _ in 0..<31 {
            seconds += 0.1
            _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        }
        pipeline.confirmField()
        seconds += 0.1
        _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        XCTAssertEqual(session.step, .stage)
        let axes = try XCTUnwrap(
            StageAxes(xDirection: CGPoint(x: 0.98, y: 0.2), yDirection: CGPoint(x: -0.05, y: 1)))
        session.completeStage(with: axes)
        XCTAssertEqual(session.step, .done)
        XCTAssertEqual(session.stageAxes, axes)
        XCTAssertEqual(session.info.stageAxes, axes)
    }

    func testHeldSetupDoesNotAdvanceAndIgnoresConfirmsAndReleasedSetupDoes() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        let frame = discFrame()
        var seconds = 0.0
        session.isHeld = true
        for _ in 0..<31 {
            seconds += 0.1
            _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        }
        pipeline.confirmField()
        for _ in 0..<5 {
            seconds += 0.1
            _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        }
        XCTAssertEqual(session.step, .field, "held: the confirmed field does not move on")
        session.confirmStep()
        session.isHeld = false
        seconds += 0.1
        _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        XCTAssertEqual(session.step, .stage, "released: it advances as before (focus is skipped)")
    }

    /// Phase 2l: redoing the field after the stage was calibrated (or skipped) forgets the
    /// straightening, so the new stage step measures in the unstraightened axes. The display's
    /// straightening is `setupInfo.stageAxes ?? .identity`, which is nil here until the new
    /// calibration is done.
    func testRedoingTheFieldForgetsTheStraighteningSoTheNextStageStepIsUnstraightened() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        let frame = discFrame()
        var seconds = 0.0
        func feed(_ count: Int) {
            for _ in 0..<count {
                seconds += 0.1
                _ = session.process(frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
            }
        }
        feed(31)
        pipeline.confirmField()
        feed(1)
        XCTAssertEqual(session.step, .stage)
        session.skipStage()
        XCTAssertEqual(session.info.stageAxes, .identity)

        session.redoField(pipeline: pipeline)
        feed(2)
        XCTAssertEqual(session.step, .field)
        XCTAssertNil(session.stageAxes)
        XCTAssertNil(session.info.stageAxes)
        feed(31)
        pipeline.confirmField()
        feed(1)
        XCTAssertEqual(session.step, .stage)
        XCTAssertNil(session.info.stageAxes, "measured unstraightened")
    }

    // MARK: Losing alignment

    private func darkFrame() -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { _, _ in 10 }
    }

    /// Feeds `seconds` of `frame` at 10 a second; returns the time reached.
    @discardableResult
    private func feed(
        _ frame: CVPixelBuffer, for duration: Double, from start: Double,
        session: LabSetupSession, pipeline: SlideMovementPipeline
    ) -> Double {
        var seconds = start
        for _ in 0..<Int((duration * 10).rounded()) {
            seconds += 0.1
            _ = session.process(
                frame, seconds: seconds, pipeline: pipeline, measureAgreement: false)
        }
        return seconds
    }

    func testALossInFocusGoesBackToAlignThenFieldAgainThenFocus() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = reachFocus(session: session, pipeline: pipeline)
        time = feed(darkFrame(), for: 1.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus, "a 1 s dip does not go back")
        time = feed(discFrame(), for: 0.5, from: time, session: session, pipeline: pipeline)
        time = feed(darkFrame(), for: 3.2, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .align)
        XCTAssertEqual(session.info.resumeStep, .field)
        time = feed(discFrame(), for: 2.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .field, "the circle moved: the mask is learned again")
        XCTAssertNil(session.info.resumeStep)
        XCTAssertLessThan(progress(pipeline), 0.3, "learning started again (a redetect)")
        time = feed(discFrame(), for: 3.2, from: time, session: session, pipeline: pipeline)
        pipeline.confirmField()
        feed(discFrame(), for: 0.2, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
    }

    func testAReadingBetweenThePassAndLostLimitsDoesNotGoBack() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = reachFocus(session: session, pipeline: pipeline)
        // One half 30% darker: fails passing (0.75); once the field is confirmed evenness and
        // glare no longer count at all.
        let uneven = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 640, Double(y) - 360) <= 300 ? (x >= 640 ? 140 : 200) : 10
        }
        time = feed(uneven, for: 6, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        XCTAssertNil(session.info.resumeStep)
    }

    func testAShiftOfQuarterRadiusInFocusGoesBackAfterThreeSecondsNotTwoAndAHalf() {
        let shifted = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 715, Double(y) - 360) <= 300 ? 200 : 10  // 75 px = 0.25 r
        }
        for (hold, goesBack) in [(2.5, false), (3.2, true)] {
            let pipeline = makePipeline()
            let session = LabSetupSession()
            var time = reachFocus(session: session, pipeline: pipeline)
            time = feed(shifted, for: hold, from: time, session: session, pipeline: pipeline)
            XCTAssertEqual(session.step == .align, goesBack, "held \(hold) s")
        }
    }

    func testALossInFieldGoesBackToAlignAndReturnsToFieldWithARedetect() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        var time = feed(discFrame(), for: 1.0, from: 0, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .field)
        XCTAssertGreaterThan(progress(pipeline), 0, "the mask is being learned")
        time = feed(darkFrame(), for: 4.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .align)
        XCTAssertEqual(session.info.resumeStep, .field)
        time = feed(discFrame(), for: 2.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .field)
        XCTAssertLessThan(progress(pipeline), 0.2, "learning started again (a redetect)")
    }

    func testRedoGoesBackToAlignWithFreshChecks() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        session.redo()
        XCTAssertEqual(session.step, .align)
        XCTAssertNil(session.info.focus)
        XCTAssertFalse(session.info.isAlignmentPassed)
        _ = session.process(
            discFrame(), seconds: 0, pipeline: pipeline, measureAgreement: false)
        XCTAssertEqual(progress(pipeline), 0)
    }

    func testTheFocusSquareIsSeventyPercentOfTheDiameterAndStaysInTheFrame() {
        let circle = FieldCircle(centre: CGPoint(x: 640, y: 360), radius: 300)
        let square = LabSetupSession.focusSquare(for: circle, frameSize: size)
        XCTAssertEqual(square.width, 420, accuracy: 1e-9)
        XCTAssertEqual(square.midX, 640, accuracy: 1e-9)
        let edge = LabSetupSession.focusSquare(
            for: FieldCircle(centre: CGPoint(x: 100, y: 100), radius: 300), frameSize: size)
        XCTAssertGreaterThanOrEqual(edge.minX, 0)
        XCTAssertGreaterThanOrEqual(edge.minY, 0)
    }

    // MARK: Timing and the previews

    func testAnalysisTimePerFrame() throws {
        let frame = discFrame()
        let grid = try XCTUnwrap(LumaGrid.sample(of: frame, step: 8))
        var check = AlignmentCheck()
        let runs = 200
        var clock = ContinuousClock.now
        for index in 0..<runs {
            _ = check.update(
                luma: grid.luma, gridWidth: grid.width, gridHeight: grid.height, gridStep: 8,
                seconds: Double(index) * 0.1)
        }
        let align = (ContinuousClock.now - clock) / runs
        let box = CGRect(x: 430, y: 150, width: 420, height: 420)
        clock = ContinuousClock.now
        var guide = FocusGuide()
        for index in 0..<runs {
            let sharpness = FrameAnalyzer.stats(of: frame, in: box, step: 4)?.sharpness ?? 0
            _ = guide.update(sharpness: sharpness, seconds: Double(index) * 0.1)
        }
        let focus = (ContinuousClock.now - clock) / runs
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        print(String(format: "SETUP TIMING align %.3f ms, focus %.3f ms per frame", ms(align), ms(focus)))
        XCTAssertLessThan(ms(align), 20)
        XCTAssertLessThan(ms(focus), 20)
    }

    func testRunMonitorAnalysisTime() throws {
        let frame = discFrame()
        let box = CGRect(x: 430, y: 150, width: 420, height: 420)
        let runs = 100
        func ms(_ duration: Duration) -> Double {
            Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        }
        var clock = ContinuousClock.now
        for _ in 0..<runs { _ = FrameAnalyzer.focusIndex(of: frame, in: box) }
        let focus = (ContinuousClock.now - clock) / runs
        let grid = try XCTUnwrap(LumaGrid.sample(of: frame, step: 8))
        clock = ContinuousClock.now
        for _ in 0..<runs {
            let sampled = LumaGrid.sample(of: frame, step: 8)
            _ = AlignmentMeasure.measure(
                luma: sampled?.luma ?? grid.luma, gridWidth: grid.width, gridHeight: grid.height,
                gridStep: 8, thresholds: AlignmentThresholds())
        }
        let alignment = (ContinuousClock.now - clock) / runs
        print(
            String(
                format: "MONITOR TIMING focus index %.3f ms, alignment (grid and measure) %.3f ms",
                ms(focus), ms(alignment)))
        XCTAssertLessThan(ms(focus), 30)
        XCTAssertLessThan(ms(alignment), 30)
    }

    @MainActor
    func testTheSetupScreensRender() throws {
        let renderer = ImageRenderer(content: SetupPreviewSheet())
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.uiImage)
        let data = try XCTUnwrap(image.pngData())
        let url = FileManager.default.temporaryDirectory.appending(path: "setup-previews.png")
        try data.write(to: url)
        print("PREVIEW \(url.path) \(Int(image.size.width))x\(Int(image.size.height))")
        XCTAssertGreaterThan(data.count, 10_000)
    }
}
