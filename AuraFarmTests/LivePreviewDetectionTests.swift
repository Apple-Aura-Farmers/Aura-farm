import CoreVideo
import XCTest

@testable import AuraFarm

/// Detections shown while the stage is moved by hand: seen, never counted.
final class LivePreviewDetectionTests: XCTestCase {
    private let size = CGSize(width: 64, height: 64)
    private let box = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)

    private func frame() -> CVPixelBuffer {
        SyntheticFrame.make(width: 64, height: 64) { _, _ in 100 }
    }

    private var found: [OrganismDetector.Detection] {
        [OrganismDetector.Detection(label: "Volvox", confidence: 0.9, box: box)]
    }

    private func preview(
        _ session: LiveCountSession, skip: String? = nil, moved: Bool = false, at seconds: Double = 1
    ) {
        session.processPreview(
            buffer: frame(), skipReason: skip, moved: moved, frameSize: size, fieldCircle: nil,
            seconds: seconds)
        session.drain()
    }

    func testPreviewResultsAreShownButChangeNothingInTheCount() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        session.setPreviewing(true)
        preview(session)
        preview(session, at: 1.3)
        let info = session.info(isActive: false, frameSize: size)
        XCTAssertTrue(info.isPreviewing)
        XCTAssertEqual(info.previewBoxes.count, 1)
        XCTAssertEqual(info.previewBoxes.first?.status, .notCounted)
        XCTAssertEqual(info.previewBoxes.first?.label, "Volvox")
        XCTAssertEqual(info.total, 0)
        XCTAssertEqual(info.tallyTotal, 0)
        XCTAssertTrue(info.dots.isEmpty, "nothing on the map")
        XCTAssertTrue(info.boxes.isEmpty)
        XCTAssertEqual(info.framesCounted, 0)
        XCTAssertTrue(info.framesSkipped.isEmpty)
        XCTAssertEqual(info.hapticCount, 0)
        XCTAssertNil(session.takeCompleted(), "no CSV row's detection")
        XCTAssertNil(session.secondsSinceDetection(at: 5), "the run's detection clock is untouched")
        XCTAssertNil(session.cropFile(forEntry: 1))
        XCTAssertEqual(session.counter.framesCounted, 0)
    }

    func testNothingShowsUnlessThePreviewIsOn() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        preview(session)
        XCTAssertTrue(session.info(isActive: false, frameSize: size).previewBoxes.isEmpty)
    }

    func testASkipReasonKeepsTheDetectorAway() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        session.setPreviewing(true)
        preview(session, skip: "no_sample")
        XCTAssertTrue(session.info(isActive: false, frameSize: size).previewBoxes.isEmpty)
        XCTAssertTrue(session.info(isActive: false, frameSize: size).framesSkipped.isEmpty)
    }

    func testAResultThatArrivesAfterTheHoldEndedIsDropped() {
        let gate = DispatchSemaphore(value: 0)
        let session = LiveCountSession(detect: { _, _ in
            gate.wait()
            return (self.found, OrganismDetector.Timing())
        })
        session.setPreviewing(true)
        session.processPreview(
            buffer: frame(), skipReason: nil, moved: false, frameSize: size, fieldCircle: nil,
            seconds: 1)
        session.setPreviewing(false)
        gate.signal()
        session.drain()
        let info = session.info(isActive: false, frameSize: size)
        XCTAssertTrue(info.previewBoxes.isEmpty)
        XCTAssertFalse(info.isPreviewing)
        XCTAssertEqual(info.tallyTotal, 0)
    }

    func testBoxesStayWhileTheViewIsStillAndClearOnceThePictureMovedWithNoNewResult() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        session.setPreviewing(true)
        preview(session, at: 1)
        preview(session, skip: "unchanged", moved: false, at: 5)
        XCTAssertEqual(session.info(isActive: false, frameSize: size).previewBoxes.count, 1)
        preview(session, skip: "too_fast", moved: true, at: 1.5)
        XCTAssertEqual(
            session.info(isActive: false, frameSize: size).previewBoxes.count, 1,
            "moved, but a result came within a second")
        preview(session, skip: "too_fast", moved: true, at: 2.6)
        XCTAssertTrue(session.info(isActive: false, frameSize: size).previewBoxes.isEmpty)
    }

    func testEndingThePreviewClearsTheBoxes() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        session.setPreviewing(true)
        preview(session)
        session.setPreviewing(false)
        let info = session.info(isActive: false, frameSize: size)
        XCTAssertTrue(info.previewBoxes.isEmpty)
        XCTAssertFalse(info.isPreviewing)
    }

    func testCountingAfterwardsWorksAsBefore() {
        let session = LiveCountSession(detect: { _, _ in (self.found, OrganismDetector.Timing()) })
        session.setPreviewing(true)
        preview(session)
        session.setPreviewing(false)
        session.setCounting(true)
        for index in 1...2 {
            _ = session.process(
                buffer: frame(), skipReason: nil, pictureMoved: .zero, trackerPosition: .zero,
                frameSize: size, fieldCircle: nil, seconds: Double(index), column: 1)
            session.drain()
        }
        XCTAssertEqual(session.counter.framesCounted, 2)
        XCTAssertEqual(session.counter.tallyTotal, 1, "seen twice: one organism")
        XCTAssertEqual(session.counter.helperTotal, 1)
    }
}
