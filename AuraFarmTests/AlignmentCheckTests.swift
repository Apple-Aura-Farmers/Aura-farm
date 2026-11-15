import XCTest

@testable import AuraFarm

/// Synthetic luma grids, 160 x 90 cells of 8 px (a 1280 x 720 frame).
final class AlignmentCheckTests: XCTestCase {
    private let width = 160
    private let height = 90
    private let background: UInt8 = 10

    private func grid(_ value: (Int, Int) -> UInt8) -> [UInt8] {
        var cells = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { cells[y * width + x] = value(x, y) }
        }
        return cells
    }

    private func inside(_ x: Int, _ y: Int, _ cx: Double, _ cy: Double, _ r: Double) -> Bool {
        hypot(Double(x) - cx, Double(y) - cy) <= r
    }

    private func disc(
        cx: Double = 80, cy: Double = 45, r: Double = 35, level: UInt8 = 200,
        modify: (Int, Int, UInt8) -> UInt8 = { $2 }
    ) -> [UInt8] {
        grid { x, y in
            inside(x, y, cx, cy, r) ? modify(x, y, level) : background
        }
    }

    private func measure(_ luma: [UInt8]) -> AlignmentReading {
        var check = AlignmentCheck()
        return check.update(
            luma: luma, gridWidth: width, gridHeight: height, gridStep: 8, seconds: 0)
    }

    func testAnEvenFullyVisibleDiscPassesButIsPassedOnlyAfterPassSeconds() {
        let frame = disc()
        let reading = measure(frame)
        XCTAssertTrue(reading.found)
        XCTAssertEqual(reading.problems, [])
        XCTAssertTrue(reading.passes)
        XCTAssertGreaterThan(reading.score, 60)
        let circle = reading.circle
        XCTAssertEqual(Double(circle?.centre.x ?? 0), 80.5 * 8, accuracy: 8)
        XCTAssertEqual(Double(circle?.centre.y ?? 0), 45.5 * 8, accuracy: 8)
        XCTAssertEqual(circle?.radius ?? 0, 35 * 8, accuracy: 12)
        XCTAssertEqual(reading.sectorMeans.count, 8)

        var check = AlignmentCheck()
        for index in 0..<20 {
            _ = check.update(
                luma: frame, gridWidth: width, gridHeight: height, gridStep: 8,
                seconds: Double(index) * 0.1)
            let expected = Double(index) * 0.1 >= 1.5 - 1e-9
            XCTAssertEqual(check.isPassed, expected, "at \(Double(index) * 0.1) s")
        }
        // A break restarts the wait.
        _ = check.update(
            luma: disc(cx: 140), gridWidth: width, gridHeight: height, gridStep: 8, seconds: 2.0)
        XCTAssertFalse(check.isPassed)
    }

    func testADiscCutOffByTheRightEdgeIsClippedRight() {
        let reading = measure(disc(cx: 140))
        XCTAssertEqual(reading.clippedSides, [.right])
        XCTAssertEqual(reading.problems.first, .clipped)
    }

    func testACrescentIsNotRound() {
        let crescent = grid { x, y in
            self.inside(x, y, 80, 45, 35) && !self.inside(x, y, 96, 45, 28) ? 200 : self.background
        }
        let reading = measure(crescent)
        XCTAssertTrue(reading.found)
        XCTAssertLessThan(reading.roundness ?? 1, 0.85)
        XCTAssertTrue(reading.problems.contains(.notRound))
    }

    func testADiscDarkerOnOneSideIsUnevenWithTheDarkestSectorThere() {
        // Darker toward +x: 240 on the left, 100 on the right.
        let reading = measure(
            disc(level: 0) { x, _, _ in UInt8(240 - 140 * Double(x - 45) / 70) })
        XCTAssertTrue(reading.problems.contains(.uneven), "\(reading.evenness ?? -1)")
        XCTAssertEqual(reading.darkestSector, 0, "sector 0 points along frame +x")
        XCTAssertEqual(reading.brightestSector, 4)
    }

    func testASmallSaturatedPatchIsGlare() {
        let reading = measure(
            disc { x, y, level in self.inside(x, y, 95, 45, 6) ? 255 : level })
        XCTAssertTrue(reading.problems.contains(.glare))
        XCTAssertGreaterThan(reading.saturatedShare ?? 0, 0.01)
    }

    func testATinyDiscOrABlackFrameIsNoCircle() {
        for frame in [disc(r: 5), [UInt8](repeating: 0, count: width * height)] {
            let reading = measure(frame)
            XCTAssertFalse(reading.found)
            XCTAssertEqual(reading.problems, [.noCircle])
            XCTAssertEqual(reading.score, 0)
        }
    }

    func testTheTrendFollowsTheScore() {
        var check = AlignmentCheck()
        func feed(_ frame: [UInt8], from start: Int, count: Int) {
            for index in start..<(start + count) {
                _ = check.update(
                    luma: frame, gridWidth: width, gridHeight: height, gridStep: 8,
                    seconds: Double(index) * 0.1)
            }
        }
        XCTAssertEqual(check.trend, .steady, "no history yet")
        feed(disc(cx: 140), from: 0, count: 20)
        XCTAssertEqual(check.trend, .steady)
        // Within the last 2 s the circle came fully into view: the score rose.
        feed(disc(), from: 20, count: 12)
        XCTAssertEqual(check.trend, .better)
        feed(disc(cx: 140), from: 32, count: 12)
        XCTAssertEqual(check.trend, .worse)
        feed(disc(cx: 140), from: 44, count: 25)
        XCTAssertEqual(check.trend, .steady)
    }
}
