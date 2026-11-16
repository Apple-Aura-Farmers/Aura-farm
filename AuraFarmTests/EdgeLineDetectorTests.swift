import XCTest

@testable import AuraFarm

/// Phase 2j part C: the edge-line detector, on synthetic luma. 200 x 200 cells at 2 px, so the
/// box is 400 px, one field.
final class EdgeLineDetectorTests: XCTestCase {
    private let cells = 200
    private let box = CGRect(x: 100, y: 100, width: 400, height: 400)
    private let normal = CGPoint(x: 1, y: 0)

    private struct Dots {
        var state: UInt64 = 12345
        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 33) / Double(1 << 31)
        }
    }

    /// Bright where `signedDistance` (cells, along the normal, from the centre) is positive,
    /// with sparse dark dots on both sides at the same density.
    private func grid(
        dots: Bool = true, ramp: Double = 0, edge: ((Double, Double) -> Double)? = nil,
        extra: ((Int, Int) -> Float?)? = nil
    ) -> EdgeLineGrid {
        var random = Dots()
        var luma = [Float](repeating: 100, count: cells * cells)
        for y in 0..<cells {
            for x in 0..<cells {
                let dx = Double(x) + 0.5 - Double(cells) / 2
                let dy = Double(y) + 0.5 - Double(cells) / 2
                var value: Float = 100 + Float(ramp * dx)
                if let edge, edge(dx, dy) > 0 { value = 200 }
                if dots, random.next() < 0.03 { value -= 40 }
                if let extra, let override = extra(x, y) { value = override }
                luma[y * cells + x] = value
            }
        }
        return EdgeLineGrid(luma: luma, width: cells, height: cells, step: 2)
    }

    private func straight(offsetCells: Double = 20, degrees: Double = 0) -> (Double, Double) -> Double {
        let radians = degrees * .pi / 180
        return { dx, dy in
            dx * cos(radians) + dy * sin(radians) - offsetCells
        }
    }

    func testAStraightEdgeWithDotsOnBothSidesIsFoundAcrossTheWholeWidth() throws {
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(edge: straight()), box: box, normal: normal))
        XCTAssertGreaterThanOrEqual(line.coverage, 0.9)
        XCTAssertTrue(line.isCandidate, "strength \(line.strength)")
        XCTAssertEqual(line.offsetFields, 20 * 2 / 400.0, accuracy: 0.03)
        XCTAssertEqual(line.sign, 1, "brighter ahead")
    }

    func testTheSameEdgeDarkerAheadHasTheOtherSign() throws {
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: grid(edge: { dx, _ in 20 - dx }), box: box, normal: normal))
        XCTAssertEqual(line.sign, -1)
        XCTAssertTrue(line.isCandidate)
    }

    func testAnEdgeTiltedEightDegreesIsFoundWithItsAngle() throws {
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: grid(edge: straight(offsetCells: 0, degrees: 8)), box: box, normal: normal))
        XCTAssertTrue(line.isCandidate, "coverage \(line.coverage) strength \(line.strength)")
        XCTAssertEqual(line.angleDegrees, 8, accuracy: 2)
    }

    func testAnIrregularSineBoundaryIsStillCovered() throws {
        let wavy: (Double, Double) -> Double = { dx, dy in
            dx - 3 * sin(2 * .pi * dy / 100)
        }
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(edge: wavy), box: box, normal: normal))
        XCTAssertGreaterThanOrEqual(line.coverage, 0.75)
    }

    func testARandomDotFieldWithNoEdgeIsNotACandidate() throws {
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(), box: box, normal: normal))
        XCTAssertFalse(line.isCandidate, "coverage \(line.coverage) strength \(line.strength)")
    }

    func testOneLongFibreOverFortyPercentOfTheWidthIsNotACandidate() throws {
        // A dark vertical fibre, 3 cells thick, over the middle 40% of the height.
        let fibre = grid(dots: true) { x, y in
            (98...100).contains(x) && (60..<140).contains(y) ? 20 : nil
        }
        let line = try XCTUnwrap(EdgeLineDetector.detect(grid: fibre, box: box, normal: normal))
        XCTAssertLessThan(line.coverage, 0.75)
        XCTAssertFalse(line.isCandidate)
    }

    func testALineMovedByTheTrackedChangeHasNearZeroResidual() throws {
        let first = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(edge: straight(offsetCells: 20)), box: box, normal: normal))
        // The line moved 10 cells (0.05 field) ahead; the tracker says the same.
        let moved = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: grid(edge: straight(offsetCells: 30)), box: box, normal: normal,
                previous: first, trackedChangeFields: 0.05))
        XCTAssertEqual(try XCTUnwrap(moved.slideResidualFields), 0, accuracy: 0.02)
    }

    func testAFixedLineWhileTheSlideMovesHasAResidualAboutTheMovement() throws {
        let first = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(edge: straight(offsetCells: 20)), box: box, normal: normal))
        let same = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: grid(edge: straight(offsetCells: 20)), box: box, normal: normal,
                previous: first, trackedChangeFields: 0.05))
        XCTAssertEqual(try XCTUnwrap(same.slideResidualFields), 0.05, accuracy: 0.02)
        XCTAssertNil(first.slideResidualFields, "no previous result, no residual")
    }

    func testASmoothIlluminationRampWithDotsIsNotACandidate() throws {
        // The eyepiece's falloff: a smooth ramp of 0.4 level a cell, same sign everywhere. The
        // 16 Nov 2026 plain sample read coverage 1.0 and strength 6 on it.
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(grid: grid(ramp: 0.4), box: box, normal: normal))
        XCTAssertFalse(line.isCandidate, "coverage \(line.coverage) strength \(line.strength)")
    }

    func testAnEdgeAcrossOnlyFiveEighthsOfTheBoxIsACandidateThroughTheLongestRun() throws {
        // The step exists only below y = -25 cells from the centre: parts 3 to 7 of 8.
        let corner: (Double, Double) -> Double = { dx, dy in dy > -25 ? dx - 20 : -1 }
        // The coverage route is switched off, so only the run can make it a candidate.
        var thresholds = EdgeLineThresholds()
        thresholds.candidateCoverage = 1.1
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: grid(edge: corner), box: box, normal: normal, thresholds: thresholds))
        XCTAssertGreaterThanOrEqual(line.longestRun, 5)
        XCTAssertTrue(line.isCandidate, "run \(line.longestRun) strength \(line.strength)")
    }

    func testTimePerCallOnAFullBox() throws {
        // Reported, not asserted tightly: simulator debug builds are far slower than a device.
        let big = EdgeLineGrid(
            luma: [Float](repeating: 100, count: 250 * 250), width: 250, height: 250, step: 2)
        let started = ContinuousClock.now
        for _ in 0..<10 {
            _ = EdgeLineDetector.detect(
                grid: big, box: CGRect(x: 0, y: 0, width: 500, height: 500), normal: normal)
        }
        let taken = ContinuousClock.now - started
        let milliseconds =
            (Double(taken.components.seconds) * 1000 + Double(taken.components.attoseconds) / 1e15)
            / 10
        print("EdgeLineDetector ms per call (250x250 cells): \(milliseconds)")
        XCTAssertLessThan(milliseconds, 500)
    }
}
