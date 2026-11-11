import XCTest

@testable import AuraFarm

final class FrameRateMeterTests: XCTestCase {
    func testRateOverTheLastSecond() {
        var meter = FrameRateMeter()
        XCTAssertEqual(meter.record(0), 0, "one frame is no rate")
        XCTAssertEqual(meter.record(0.1), 10, accuracy: 0.001)
        for step in 2...5 { _ = meter.record(Double(step) * 0.1) }
        XCTAssertEqual(meter.record(0.6), 10, accuracy: 0.001)
    }

    func testOldFramesFallOutOfTheWindow() {
        var meter = FrameRateMeter()
        for step in 0..<10 { _ = meter.record(Double(step) * 0.1) }
        // A long gap: only the frame just recorded is inside the last second.
        XCTAssertEqual(meter.record(5), 0)
        XCTAssertEqual(meter.record(5.5), 2, accuracy: 0.001)
    }

    func testReset() {
        var meter = FrameRateMeter()
        _ = meter.record(0)
        meter.reset()
        XCTAssertEqual(meter.record(0.1), 0)
    }
}
