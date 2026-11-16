import XCTest

@testable import AuraFarm

/// Phase 2k part B: a few distinct particles on bright glass average to a low variance but are
/// plenty to follow. 256 px frames, the box is the 179 px centre square.
final class SparseTrackingTests: XCTestCase {
    private let size = 256
    private lazy var frameSize = CGSize(width: size, height: size)
    private lazy var box = EyepieceField.centreSquare(frameSize: frameSize)
    private var seconds = 0.0

    /// Dark particle positions spread over three quarters of the box, one per feature cell.
    private let spread = [(60, 60), (100, 70), (170, 60), (180, 120), (70, 170), (110, 190)]
    /// All in the top-left quarter.
    private let oneQuarter = [(50, 50), (70, 50), (90, 50), (50, 70), (70, 70), (90, 70)]

    private func frame(dots: [(Int, Int)], shiftedBy dx: Int = 0, noise: Int = 0) -> CVPixelBuffer {
        let jitter = SyntheticFrame.noise(width: size, height: size)
        return SyntheticFrame.make(width: size, height: size) { [size] x, y in
            var value = 220
            // Each particle a little different in darkness, so registration cannot mistake one
            // for another.
            for (index, (cx, cy)) in dots.enumerated()
            where abs(x - dx - cx) <= 2 && abs(y - cy) <= 2 {
                value = 220 - 26 - 3 * index
            }
            if noise > 0 { value += Int(jitter[y * size + x]) % (2 * noise + 1) - noise }
            return UInt8(value)
        }
    }

    private func measure(_ buffer: CVPixelBuffer) -> (sharpness: Double, features: FeatureCells) {
        let sharpness = FrameAnalyzer.stats(of: buffer, in: box, step: SlideTracker.statsStep)?.sharpness ?? 0
        let features =
            FrameAnalyzer.featureCells(of: buffer, in: box, featureContrast: 40) ?? FeatureCells()
        return (sharpness, features)
    }

    private func detail(_ buffer: CVPixelBuffer, tracksSparse: Bool) -> Bool {
        var thresholds = DetailThresholds()
        thresholds.tracksSparse = tracksSparse
        var check = DetailCheck(thresholds: thresholds)
        let seen = measure(buffer)
        for _ in 0..<5 { check.update(boxSharpness: seen.sharpness, features: seen.features) }
        return check.hasDetail
    }

    func testSixDistinctDotsOverThreeQuartersHaveDetailOnlyWithTheToggleOn() {
        let buffer = frame(dots: spread)
        let seen = measure(buffer)
        XCTAssertLessThan(seen.sharpness, 120, "premise: the variance alone says no detail")
        XCTAssertGreaterThanOrEqual(seen.sharpness, 30, "sharpness \(seen.sharpness)")
        XCTAssertGreaterThanOrEqual(seen.features.cells, 4, "cells \(seen.features)")
        XCTAssertGreaterThanOrEqual(seen.features.quarters, 2)
        XCTAssertTrue(detail(buffer, tracksSparse: true))
        XCTAssertFalse(detail(buffer, tracksSparse: false))
    }

    func testBlankGlassWithNoiseHasNoDetail() {
        let buffer = frame(dots: [], noise: 3)
        XCTAssertEqual(measure(buffer).features.cells, 0)
        XCTAssertFalse(detail(buffer, tracksSparse: true))
    }

    func testSixDotsAllInOneQuarterHaveNoDetail() {
        let buffer = frame(dots: oneQuarter)
        XCTAssertEqual(measure(buffer).features.quarters, 1)
        XCTAssertFalse(detail(buffer, tracksSparse: true))
    }

    func testASparseSequenceWithASteadyShiftIsTrackedAndBlankGlassStillFreezes() {
        let tracker = SlideTracker()
        func track(_ buffer: CVPixelBuffer) -> SlideTrackerReading {
            seconds += 0.1
            return tracker.track(buffer, box: box, frameSize: frameSize, seconds: seconds)
        }
        var reading = track(frame(dots: spread))
        for index in 1...6 {
            reading = track(frame(dots: spread, shiftedBy: index * 2))
        }
        XCTAssertTrue(reading.hasDetail)
        XCTAssertTrue(reading.sparse)
        XCTAssertEqual(reading.trackingState, .tracking)
        XCTAssertEqual(reading.position.x, 12, accuracy: 3, "the position follows the dots")
        let before = reading.position
        for _ in 0..<5 { reading = track(frame(dots: [], noise: 3)) }
        XCTAssertEqual(reading.trackingState, .paused)
        XCTAssertFalse(reading.sparse)
        XCTAssertEqual(reading.position, before, "empty glass freezes the position")
    }
}
