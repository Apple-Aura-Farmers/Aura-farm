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

    func testAlignAndFocusNeitherLearnTheMaskNorTrackAndFieldStartsLearning() {
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

        // Align: 1.5 s of a whole, round, even disc passes it.
        let align = feed(14)
        XCTAssertEqual(session.step, .align)
        XCTAssertTrue(align.allSatisfy(isSetup), "no frame went to the pipeline")
        XCTAssertEqual(progress(pipeline), 0, "no mask learning in align")
        _ = feed(4)
        XCTAssertEqual(session.step, .focus)
        XCTAssertTrue(session.info.isAlignmentPassed)

        // Focus: a flat disc has no sharpness peak, so it stays here; still nothing learns.
        let focus = feed(30)
        XCTAssertEqual(session.step, .focus)
        XCTAssertTrue(focus.allSatisfy(isSetup))
        XCTAssertEqual(progress(pipeline), 0, "no mask learning in focus")
        XCTAssertNotNil(session.info.focusSquare)
        XCTAssertNotNil(session.info.focus)
        XCTAssertFalse(session.log.isEmpty)
        XCTAssertTrue(session.log.contains { $0.step == .focus && $0.focus != nil })

        // Field: the frames go to the pipeline, which starts learning.
        session.redoField(pipeline: pipeline)
        XCTAssertEqual(session.step, .field)
        let field = feed(5)
        XCTAssertTrue(field.allSatisfy(isTracked))
        XCTAssertGreaterThan(progress(pipeline), 0, "learning started")
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

    func testALossInFocusGoesBackToAlignAndReturnsToFocus() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = feed(discFrame(), for: 2.0, from: 0, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        time = feed(darkFrame(), for: 1.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus, "a 1 s dip does not go back")
        time = feed(discFrame(), for: 0.5, from: time, session: session, pipeline: pipeline)
        time = feed(darkFrame(), for: 2.2, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .align)
        XCTAssertEqual(session.info.resumeStep, .focus)
        XCTAssertEqual(progress(pipeline), 0, "nothing learns while aligning again")
        feed(discFrame(), for: 2.0, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        XCTAssertNil(session.info.resumeStep)
    }

    func testAReadingBetweenThePassAndLostLimitsDoesNotGoBack() {
        let pipeline = makePipeline()
        let session = LabSetupSession()
        var time = feed(discFrame(), for: 2.0, from: 0, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        // One half 30% darker: fails passing (0.75) but not the looser limit (0.65).
        let uneven = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 640, Double(y) - 360) <= 300 ? (x >= 640 ? 140 : 200) : 10
        }
        time = feed(uneven, for: 6, from: time, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .focus)
        XCTAssertNil(session.info.resumeStep)
    }

    func testALossInFieldGoesBackToAlignAndReturnsToFieldWithARedetect() {
        let pipeline = makePipeline()
        let session = LabSetupSession(skippingAlignAndFocus: true)
        var time = feed(discFrame(), for: 1.0, from: 0, session: session, pipeline: pipeline)
        XCTAssertEqual(session.step, .field)
        XCTAssertGreaterThan(progress(pipeline), 0, "the mask is being learned")
        time = feed(darkFrame(), for: 3.0, from: time, session: session, pipeline: pipeline)
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
