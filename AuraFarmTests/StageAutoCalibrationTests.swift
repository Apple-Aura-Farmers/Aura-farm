import XCTest

@testable import AuraFarm

final class StageAutoCalibrationTests: XCTestCase {
    /// Feeds both servos a run of tracked samples: `vx`/`vy` fields per degree.
    private func calibrate(vx: CGPoint, vy: CGPoint, degrees: Int = 12) -> StageAutoCalibration {
        var c = StageAutoCalibration()
        for (servo, v) in [(StageAxis.x, vx), (StageAxis.y, vy)] {
            for d in stride(from: 0, through: degrees, by: 3) {
                let a = Double(90 + d)
                c.add(
                    servo: servo, angle: a,
                    position: CGPoint(x: v.x * CGFloat(d), y: v.y * CGFloat(d)), tracking: .tracking)
            }
        }
        return c
    }

    private func mapping(_ vx: CGPoint, _ vy: CGPoint) throws -> StageServoMapping {
        try calibrate(vx: vx, vy: vy).mapping().get()
    }

    func testStraight() throws {
        let m = try mapping(CGPoint(x: 0.2, y: 0), CGPoint(x: 0, y: 0.2))
        XCTAssertFalse(m.swapped)
        XCTAssertEqual(m.axes.tiltDegrees, 0, accuracy: 0.01)
        XCTAssertEqual(m.x.x, 0.2, accuracy: 1e-6)
    }

    func testSwapped() throws {
        let m = try mapping(CGPoint(x: 0, y: 0.2), CGPoint(x: 0.2, y: 0))
        XCTAssertTrue(m.swapped)
        XCTAssertEqual(m.axes.xDirection.x, 1, accuracy: 1e-6)
        XCTAssertEqual(m.axes.yDirection.y, 1, accuracy: 1e-6)
    }

    func testReversedSign() throws {
        let m = try mapping(CGPoint(x: -0.2, y: 0), CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(m.axes.xDirection.x, 1, accuracy: 1e-6)
        let d = try XCTUnwrap(m.degrees(forMove: CGPoint(x: 1, y: 0)))
        XCTAssertLessThan(d.x, 0)
    }

    func testTilt() throws {
        let t = 10.0 * .pi / 180
        let m = try mapping(
            CGPoint(x: 0.2 * cos(t), y: 0.2 * sin(t)), CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(m.axes.tiltDegrees, 10, accuracy: 0.01)
    }

    func testParallelFails() {
        let c = calibrate(vx: CGPoint(x: 0.2, y: 0), vy: CGPoint(x: 0.2, y: 0.01))
        XCTAssertEqual(c.mapping(), .failure(.parallel))
    }

    func testTooLittleTravelFails() {
        let c = calibrate(vx: CGPoint(x: 0.01, y: 0), vy: CGPoint(x: 0, y: 0.2))
        XCTAssertEqual(c.mapping(), .failure(.barelyMoves(.x)))
    }

    func testLostTracking() {
        var c = StageAutoCalibration()
        for d in 0..<6 {
            c.add(servo: .x, angle: Double(90 + d), position: .zero, tracking: .lost)
        }
        XCTAssertEqual(c.vector(for: .x), .failure(.lostTracking))
    }

    func testSlackIsSkipped() throws {
        var c = StageAutoCalibration()
        for i in 0..<6 {
            c.add(servo: .x, angle: Double(90 + 3 * i), position: .zero, tracking: .tracking)
        }
        for i in 1...10 {
            c.add(
                servo: .x, angle: Double(105 + 3 * i),
                position: CGPoint(x: 0.02 * Double(3 * i), y: 0), tracking: .tracking)
        }
        let v = try c.vector(for: .x).get()
        XCTAssertEqual(v.x, 0.02, accuracy: 1e-6)
        XCTAssertEqual(v.y, 0, accuracy: 1e-6)
        XCTAssertEqual(c.slackDegrees(of: .x), 15, accuracy: 1e-6)
        XCTAssertGreaterThanOrEqual(c.travel(of: .x), c.minTravelFields)
    }

    /// A tracking gap re-anchors the tracker, so the position misses the motion in the gap:
    /// each run keeps its own offset and the travel adds up.
    func testGapStartsNewRun() throws {
        var c = StageAutoCalibration()
        for i in 0...5 {
            c.add(
                servo: .x, angle: Double(90 + 3 * i), position: CGPoint(x: 0.06 * Double(i), y: 0),
                tracking: .tracking)
        }
        // Three steps lost in the gap: the position carries on from 0.30 instead of 0.48.
        for i in 0...5 {
            c.add(
                servo: .x, angle: Double(114 + 3 * i),
                position: CGPoint(x: 0.30 + 0.06 * Double(i), y: 0), tracking: .tracking,
                afterGap: i == 0)
        }
        let v = try c.vector(for: .x).get()
        XCTAssertEqual(v.x, 0.02, accuracy: 1e-6)
        XCTAssertEqual(c.travel(of: .x), 0.6, accuracy: 1e-6)
    }

    func testSolveReproducesTarget() throws {
        let t = 7.0 * .pi / 180
        let m = try mapping(CGPoint(x: 0.2 * cos(t), y: 0.2 * sin(t)), CGPoint(x: -0.03, y: 0.18))
        let target = CGPoint(x: 1.2, y: -0.7)
        let d = try XCTUnwrap(m.degrees(forMove: target))
        let back = CGPoint(
            x: m.x.x * d.x + m.y.x * d.y, y: m.x.y * d.x + m.y.y * d.y)
        XCTAssertEqual(back.x, target.x, accuracy: 1e-6)
        XCTAssertEqual(back.y, target.y, accuracy: 1e-6)
    }

    func testMovingAnglesSkipSlack() {
        var c = StageAutoCalibration()
        for i in 0..<6 {
            c.add(servo: .x, angle: Double(90 + 3 * i), position: .zero, tracking: .tracking)
        }
        for i in 1...3 {
            c.add(
                servo: .x, angle: Double(105 + 3 * i),
                position: CGPoint(x: 0.1 * Double(i), y: 0), tracking: .tracking)
        }
        // The onset sample (105) and the three moving ones.
        XCTAssertEqual(c.movingAngles(of: .x), 4)
    }

    func testStageStepSweep() throws {
        let sweep = try XCTUnwrap(
            StageAutoCalibration.stageStepSweep(fieldsPerDegree: 0.026, slackDegrees: 18))
        XCTAssertEqual(sweep.end - sweep.start, 111)
        XCTAssertEqual(Double(sweep.start + sweep.end) / 2, 90, accuracy: 1)
        let near = try XCTUnwrap(
            StageAutoCalibration.stageStepSweep(
                fieldsPerDegree: 0.026, slackDegrees: 18, centre: 170))
        XCTAssertEqual(near.end, 180)
        XCTAssertEqual(near.end - near.start, 111)
        XCTAssertNil(StageAutoCalibration.stageStepSweep(fieldsPerDegree: 0.01, slackDegrees: 0))
        XCTAssertNil(StageAutoCalibration.stageStepSweep(fieldsPerDegree: 0, slackDegrees: 0))
    }

    func testSweepWithAFirstStepLurchKeepsTheTrueSlope() throws {
        var c = StageAutoCalibration()
        // 40 samples over 120 degrees at 0.02 field/degree; the first moving step lurches 0.8.
        for i in 0..<40 {
            let angle = Double(i) * 120.0 / 39.0
            let lurch = i >= 1 ? 0.8 : 0.0
            c.add(
                servo: .x, angle: angle, position: CGPoint(x: 0.02 * angle + lurch, y: 0),
                tracking: .tracking)
        }
        let v = try c.vector(for: .x).get()
        XCTAssertEqual(Double(v.x), 0.02, accuracy: 0.002)
        XCTAssertEqual(Double(v.y), 0, accuracy: 1e-9)
    }
}
