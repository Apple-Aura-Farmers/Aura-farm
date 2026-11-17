import XCTest

@testable import AuraFarm

/// `SlideTracker` on its own, without the lab's pipeline. Real Vision on synthetic frames,
/// with the test seams where Vision is not reliable enough.
final class SlideTrackerTests: XCTestCase {
    private let size = 256
    private lazy var texture = SyntheticFrame.smoothNoise(size: size)
    private lazy var frameSize = CGSize(width: size, height: size)
    private lazy var box = EyepieceField.centreSquare(frameSize: frameSize)
    private var seconds = 0.0

    private func frame(shiftedBy dx: Int) -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [size, texture] x, y in
            UInt8(texture[y * size + min(max(x - dx, 0), size - 1)])
        }
    }

    private func flatFrame() -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { _, _ in 90 }
    }

    @discardableResult
    private func track(_ tracker: SlideTracker, _ buffer: CVPixelBuffer) -> SlideTrackerReading {
        seconds += 0.1
        return tracker.track(buffer, box: box, frameSize: frameSize, seconds: seconds)
    }

    func testHopsAccumulate() {
        let tracker = SlideTracker()
        var reading = track(tracker, frame(shiftedBy: 0))
        for index in 1..<12 { reading = track(tracker, frame(shiftedBy: index * 15)) }
        XCTAssertEqual(reading.hops, 3)
        XCTAssertEqual(reading.position.x, 165, accuracy: 3)
        XCTAssertEqual(reading.boxSide, 179)
        XCTAssertEqual(reading.hopLimit, 179 * 0.25, accuracy: 0.001)
        XCTAssertEqual(reading.trackingState, .tracking)
        XCTAssertEqual(reading.unconfirmedGaps, 0)
    }

    func testAFalseJumpBecomesPredicted() {
        let tracker = SlideTracker()
        tracker.anchorReadingOverride = { index, measured in
            index == 3 ? CGPoint(x: 90, y: 0) : measured
        }
        var readings: [String] = []
        for index in 0..<6 { readings.append(track(tracker, frame(shiftedBy: index * 6)).reading) }
        XCTAssertEqual(readings, ["missing", "measured", "measured", "predicted", "measured", "measured"])
    }

    func testNoDetailPausesWithoutAddingDistance() {
        let tracker = SlideTracker()
        for index in 0..<4 { track(tracker, frame(shiftedBy: index * 5)) }
        var reading = track(tracker, frame(shiftedBy: 20))
        let before = reading.position
        for _ in 0..<6 { reading = track(tracker, flatFrame()) }
        XCTAssertFalse(reading.hasDetail)
        XCTAssertEqual(reading.trackingState, .paused)
        XCTAssertEqual(reading.position, before)
        XCTAssertFalse(reading.isLost)
        XCTAssertEqual(reading.blindStretches, 1)
    }

    // MARK: Blank returns

    private let ringBox = CGRect(x: 465, y: 185, width: 358, height: 358)
    private let ringSize = CGSize(width: 1280, height: 720)
    private lazy var ringTexture = SyntheticFrame.smoothNoise(size: 1280)

    private func ringFrame(shiftedBy dx: Int) -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { [ringTexture] x, y in
            guard hypot(Double(x) - 640, Double(y) - 360) <= 285 else { return 2 }
            return UInt8(70 + ringTexture[y * 1280 + min(max(x - dx, 0), 1279)] * 0.5)
        }
    }

    private func ringBlank() -> CVPixelBuffer {
        SyntheticFrame.make(width: 1280, height: 720) { x, y in
            hypot(Double(x) - 640, Double(y) - 360) <= 285 ? 90 : 2
        }
    }

    private func trackRing(_ tracker: SlideTracker, _ buffer: CVPixelBuffer) -> SlideTrackerReading {
        seconds += 0.1
        return tracker.track(buffer, box: ringBox, frameSize: ringSize, seconds: seconds)
    }

    private func intoTheBlank(_ tracker: SlideTracker) {
        for _ in 0..<4 { _ = trackRing(tracker, ringFrame(shiftedBy: 0)) }
        for _ in 0..<6 { _ = trackRing(tracker, ringBlank()) }
    }

    func testAMatchedBlankReturnRecoversThePosition() {
        let tracker = SlideTracker()
        intoTheBlank(tracker)
        var states: [TrackingState] = []
        var reading = trackRing(tracker, ringFrame(shiftedBy: 60))
        for _ in 0..<8 {
            states.append(reading.trackingState)
            reading = trackRing(tracker, ringFrame(shiftedBy: 60))
        }
        XCTAssertTrue(states.contains(.matching))
        XCTAssertEqual(reading.blankReturnsMatched, 1)
        XCTAssertEqual(reading.blankReturnsUnmatched, 0)
        XCTAssertEqual(reading.unconfirmedGaps, 0)
        XCTAssertEqual(reading.position.x, 60, accuracy: 12)
    }

    func testAnUnmatchedBlankReturnIsCounted() {
        let tracker = SlideTracker()
        intoTheBlank(tracker)
        var reading = trackRing(tracker, ringFrame(shiftedBy: 200))
        for _ in 0..<14 { reading = trackRing(tracker, ringFrame(shiftedBy: 200)) }
        XCTAssertEqual(reading.blankReturnsUnmatched, 1)
        XCTAssertEqual(reading.blankReturnsMatched, 0)
        XCTAssertEqual(reading.unconfirmedGaps, 1)
        XCTAssertEqual(reading.position.x, 0, accuracy: 12, "carries on from the last known position")
    }

    // MARK: Reference picture

    func testTheReferencePictureCheckConfirms() {
        let tracker = SlideTracker()
        track(tracker, frame(shiftedBy: 0))
        tracker.setReferencePicture()
        var reading = track(tracker, frame(shiftedBy: 0))
        XCTAssertEqual(reading.pictureCheck, "matching")
        for _ in 0..<5 { reading = track(tracker, frame(shiftedBy: 0)) }
        XCTAssertEqual(reading.pictureCheck, "confirmed")
        XCTAssertEqual(try XCTUnwrap(reading.referenceMatch).x, 0, accuracy: 4)
        XCTAssertEqual(try XCTUnwrap(reading.trueOffReferenceFields), 0, accuracy: 0.03)
    }

    func testARejectedReferenceCheckStartsAgainInsteadOfSticking() throws {
        let tracker = SlideTracker()
        // 10 readings that never agree (more than `maxReadings`), then ones that do.
        tracker.referenceReadingOverride = { index, _ in
            if index <= 10 { return CGPoint(x: index.isMultiple(of: 2) ? 60 : -60, y: 0) }
            return CGPoint(x: 5, y: 0)
        }
        track(tracker, frame(shiftedBy: 0))
        tracker.setReferencePicture()
        var states: [String] = []
        for _ in 0..<16 { states.append(track(tracker, frame(shiftedBy: 0)).pictureCheck) }
        XCTAssertFalse(states.contains("out_of_range"), "it must recover without leaving range")
        XCTAssertEqual(states.first, "matching")
        XCTAssertEqual(states.last, "confirmed")
    }

    func testResetClearsEverythingIncludingTheReferencePicture() {
        let tracker = SlideTracker()
        for index in 0..<8 { track(tracker, frame(shiftedBy: index * 15)) }
        tracker.setReferencePicture()
        track(tracker, frame(shiftedBy: 120))
        tracker.reset()
        var reading = track(tracker, frame(shiftedBy: 0))
        XCTAssertEqual(reading.hops, 0)
        XCTAssertEqual(reading.position, .zero)
        XCTAssertEqual(reading.pictureCheck, "none")
        XCTAssertEqual(reading.blindStretches, 0)
        reading = track(tracker, frame(shiftedBy: 0))
        XCTAssertEqual(reading.pictureCheck, "none", "the picture is gone, not just paused")
    }

    // MARK: Stats and conveniences

    func testBoxStatsAreSampledAtStatsStepInsideTheBox() throws {
        let buffer = frame(shiftedBy: 0)
        let reading = SlideTracker().track(buffer, box: box, frameSize: frameSize, seconds: 0)
        XCTAssertEqual(SlideTracker.statsStep, 4)
        XCTAssertEqual(
            reading.boxStats,
            try XCTUnwrap(FrameAnalyzer.stats(of: buffer, in: box, step: SlideTracker.statsStep)))
        XCTAssertNotEqual(
            reading.boxStats, try XCTUnwrap(FrameAnalyzer.stats(of: buffer, in: box, step: 2)))
    }

    func testIdleReadsTheCountersWithoutTracking() {
        let tracker = SlideTracker()
        let reading = tracker.idle(frame(shiftedBy: 0), box: nil, frameSize: frameSize)
        XCTAssertEqual(reading.boxSide, 256)
        XCTAssertEqual(reading.hopLimit, 256 * 0.3, accuracy: 0.001)
        XCTAssertNil(reading.frameShift)
        XCTAssertEqual(reading.reading, "missing")
    }

    func testTrackingStateUnconfirmedGapsAndScreenFields() {
        let stats = FrameStats(brightness: 0, sharpness: 0, contrast: 0)
        var reading = SlideTrackerReading(boxStats: stats)
        XCTAssertEqual(reading.trackingState, .tracking)
        reading.isLost = true
        XCTAssertEqual(reading.trackingState, .lost)
        reading.reading = "matching"
        XCTAssertEqual(reading.trackingState, .matching)
        reading.hasDetail = false
        XCTAssertEqual(reading.trackingState, .paused)

        reading.gaps = 2
        reading.blankReturnsUnmatched = 3
        XCTAssertEqual(reading.unconfirmedGaps, 5)

        reading.position = CGPoint(x: 100, y: 0)
        reading.boxSide = 200
        XCTAssertEqual(reading.screenFields(mapping: .asIs, mirrored: false), CGPoint(x: 0.5, y: 0))
        XCTAssertEqual(reading.screenFields(mapping: .rotateRight, mirrored: false), CGPoint(x: 0, y: 0.5))
        XCTAssertEqual(reading.screenFields(mapping: .asIs, mirrored: true), CGPoint(x: -0.5, y: 0))
        reading.boxSide = 0
        XCTAssertEqual(reading.screenFields(mapping: .asIs, mirrored: false), CGPoint(x: 100, y: 0))
    }
}
