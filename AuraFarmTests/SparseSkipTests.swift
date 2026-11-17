import XCTest

@testable import AuraFarm

/// Phase 2p part A: a frame with almost no features cannot be registered (16 Nov 2026 15:32: frames
/// with 0 to 11 feature cells were "measured" at 38 to 53 px a frame and the position jumped, while
/// frames with 22 to 34 cells tracked normally). It is skipped like a ghost frame.
final class SparseSkipTests: XCTestCase {
    private let size = 256
    private lazy var texture = SyntheticFrame.smoothNoise(size: size)
    private lazy var frameSize = CGSize(width: size, height: size)
    private lazy var box = EyepieceField.centreSquare(frameSize: frameSize)
    private var seconds = 0.0

    /// A well-textured frame: many feature cells.
    private func good() -> CVPixelBuffer {
        SyntheticFrame.make(width: size, height: size) { [size, texture] x, y in
            UInt8(texture[y * size + x])
        }
    }

    /// A few dots on bright glass: detail is "on" (sharpness about 137, over the 120 limit and
    /// under the 150 sparse-skip limit) but only about four feature cells. Phase 2q: the dots
    /// used to be 120 (sharpness about 453), which the new rule no longer skips; `dots` 120 is
    /// the sharp variant.
    private func junk(dots value: UInt8 = 165) -> CVPixelBuffer {
        let dots = [(70, 70), (150, 80), (90, 160), (160, 170)]
        return SyntheticFrame.make(width: size, height: size) { x, y in
            for (cx, cy) in dots where abs(x - cx) <= 2 && abs(y - cy) <= 2 { return value }
            return 220
        }
    }

    private func track(_ tracker: SlideTracker, _ buffer: CVPixelBuffer) -> SlideTrackerReading {
        seconds += 0.1
        return tracker.track(buffer, box: box, frameSize: frameSize, seconds: seconds)
    }

    func testThePremiseTheJunkFrameHasDetailButFewFeatureCells() throws {
        let cells = try XCTUnwrap(
            FrameAnalyzer.featureCells(of: junk(), in: box, featureContrast: 40))
        XCTAssertLessThan(cells.cells, GhostFrameThresholds().minFeatureCellsToRegister)
        let sharpness = try XCTUnwrap(FrameAnalyzer.stats(of: junk(), in: box, step: 4)).sharpness
        XCTAssertGreaterThanOrEqual(sharpness, DetailThresholds().minBoxSharpness)
        let good = try XCTUnwrap(
            FrameAnalyzer.featureCells(of: good(), in: box, featureContrast: 40))
        XCTAssertGreaterThanOrEqual(good.cells, 12, "textured frames register")
    }

    func testJunkFramesWithBigShiftsDoNotMoveThePosition() {
        let tracker = SlideTracker()
        // Whatever registration would say on a junk frame, it is not asked.
        tracker.frameShiftOverride = { _, measured in measured ?? .zero }
        tracker.anchorReadingOverride = { _, _ in CGPoint(x: 45, y: 0) }
        var last = track(tracker, good())
        for _ in 0..<5 { last = track(tracker, good()) }
        let before = last.position
        var junkReadings: [SlideTrackerReading] = []
        for index in 0..<3 {
            tracker.anchorReadingOverride = { _, _ in CGPoint(x: index.isMultiple(of: 2) ? 45 : -45, y: 0) }
            junkReadings.append(track(tracker, junk()))
        }
        XCTAssertTrue(junkReadings.allSatisfy { $0.reading == "sparse_skip" })
        XCTAssertTrue(junkReadings.allSatisfy { $0.position == before })
        XCTAssertEqual(junkReadings.last?.sparseSkips, 3)
        // A skipped frame reports no movement, so a helper who has stopped is still (the hold on an
        // aligned spot starts) however long the picture stays near empty.
        XCTAssertTrue(junkReadings.allSatisfy { $0.frameShift == .zero })
        XCTAssertTrue(junkReadings.allSatisfy { $0.hasDetail })
        tracker.anchorReadingOverride = nil
        for _ in 0..<3 { last = track(tracker, good()) }
        XCTAssertEqual(last.position.x, before.x, accuracy: 3)
        XCTAssertNotEqual(last.reading, "sparse_skip")
        XCTAssertEqual(last.sparseSkips, 3, "the count only grows with skips")
    }

    func testFiveJunkFramesInARowGoToTheNoDetailPause() {
        let tracker = SlideTracker()
        for _ in 0..<4 { _ = track(tracker, good()) }
        var readings: [SlideTrackerReading] = []
        for _ in 0..<5 { readings.append(track(tracker, junk())) }
        XCTAssertTrue(readings.prefix(4).allSatisfy { $0.hasDetail })
        XCTAssertFalse(readings[4].hasDetail)
        XCTAssertEqual(readings[4].trackingState, .paused)
        XCTAssertEqual(readings[4].blindStretches, 1)
    }

    func testTexturedFramesAreNeverSkipped() {
        let tracker = SlideTracker()
        var last = track(tracker, good())
        for _ in 0..<10 { last = track(tracker, good()) }
        XCTAssertEqual(last.sparseSkips, 0)
        XCTAssertNotEqual(last.reading, "sparse_skip")
    }

    // MARK: Phase 2q part A: skip only when the box is also blurry or flat

    func testFewCellsButASharpBoxIsRegisteredNormally() throws {
        // 22:04 dark lighting: the cells read low on a sharp box (median sharpness 370).
        let sharp = junk(dots: 120)
        let cells = try XCTUnwrap(FrameAnalyzer.featureCells(of: sharp, in: box, featureContrast: 40))
        XCTAssertLessThan(cells.cells, GhostFrameThresholds().minFeatureCellsToRegister)
        let sharpness = try XCTUnwrap(FrameAnalyzer.stats(of: sharp, in: box, step: 4)).sharpness
        XCTAssertGreaterThan(sharpness, GhostFrameThresholds().maxSharpnessForSparseSkip)
        let tracker = SlideTracker()
        for _ in 0..<4 { _ = track(tracker, good()) }
        let readings = (0..<3).map { _ in track(tracker, sharp) }
        XCTAssertTrue(readings.allSatisfy { $0.reading != "sparse_skip" })
        XCTAssertEqual(readings.last?.sparseSkips, 0)
    }

    func testFewCellsAndABlurryBoxIsStillSkipped() throws {
        let sharpness = try XCTUnwrap(FrameAnalyzer.stats(of: junk(), in: box, step: 4)).sharpness
        XCTAssertLessThan(sharpness, GhostFrameThresholds().maxSharpnessForSparseSkip)
        let tracker = SlideTracker()
        for _ in 0..<4 { _ = track(tracker, good()) }
        let readings = (0..<3).map { _ in track(tracker, junk()) }
        XCTAssertTrue(readings.allSatisfy { $0.reading == "sparse_skip" })
    }

    func testTheDefaultLimitIsBetweenTheJunkAndTheDarkLightingFrames() {
        let limit = GhostFrameThresholds().maxSharpnessForSparseSkip
        XCTAssertGreaterThan(limit, 60, "15:32 junk read 15 to 60")
        XCTAssertLessThan(limit, 370, "22:04 wrongly skipped frames had a median of 370")
    }
}
