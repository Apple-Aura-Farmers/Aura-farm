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

    func testFieldConfirmedMovesOnToDone() {
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
        XCTAssertEqual(session.step, .done)
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
