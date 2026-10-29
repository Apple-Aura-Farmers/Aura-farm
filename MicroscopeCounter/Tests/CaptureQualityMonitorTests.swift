import XCTest

@testable import MicroscopeCounter

final class CaptureQualityMonitorTests: XCTestCase {
    private let good = CaptureQualityReading(brightness: 120, sharpness: 300, shakePixels: 0.5)
    private let dark = CaptureQualityReading(brightness: 20, sharpness: 5, shakePixels: 0.5)
    private let blurry = CaptureQualityReading(brightness: 120, sharpness: 10, shakePixels: 0.5)
    private let shaky = CaptureQualityReading(brightness: 120, sharpness: 300, shakePixels: 9)

    private func feed(_ reading: CaptureQualityReading, times: Int, into monitor: CaptureQualityMonitor) {
        for _ in 0..<times { monitor.update(with: reading) }
    }

    func testNotReadyUntilSettled() {
        let monitor = CaptureQualityMonitor()
        feed(good, times: monitor.thresholds.readingsToClear - 1, into: monitor)
        XCTAssertFalse(monitor.isReady)
        feed(good, times: 1, into: monitor)
        XCTAssertTrue(monitor.isReady)
    }

    func testSingleBadReadingDoesNotRaiseIssue() {
        let monitor = CaptureQualityMonitor()
        feed(good, times: 10, into: monitor)
        feed(blurry, times: 1, into: monitor)
        XCTAssertTrue(monitor.activeIssues.isEmpty)
        XCTAssertTrue(monitor.isReady)
    }

    func testRaisesAfterConsecutiveBadReadings() {
        let monitor = CaptureQualityMonitor()
        feed(good, times: 10, into: monitor)
        feed(blurry, times: monitor.thresholds.readingsToRaise, into: monitor)
        XCTAssertEqual(monitor.activeIssues, [.blurry])
        XCTAssertFalse(monitor.isReady)
    }

    func testClearsOnlyAfterConsecutiveGoodReadings() {
        let monitor = CaptureQualityMonitor()
        feed(shaky, times: monitor.thresholds.readingsToRaise, into: monitor)
        XCTAssertEqual(monitor.activeIssues, [.shaky])

        feed(good, times: monitor.thresholds.readingsToClear - 1, into: monitor)
        XCTAssertEqual(monitor.activeIssues, [.shaky])

        feed(good, times: 1, into: monitor)
        XCTAssertTrue(monitor.activeIssues.isEmpty)
    }

    func testDarkImageIsNotAlsoReportedAsBlurry() {
        let monitor = CaptureQualityMonitor()
        feed(dark, times: 10, into: monitor)
        XCTAssertEqual(monitor.activeIssues, [.tooDark])
        XCTAssertEqual(monitor.topIssue, .tooDark)
    }

    func testTopIssueFollowsPriorityOrder() {
        let monitor = CaptureQualityMonitor()
        let blurryAndShaky = CaptureQualityReading(brightness: 120, sharpness: 10, shakePixels: 9)
        feed(blurryAndShaky, times: monitor.thresholds.readingsToRaise, into: monitor)
        XCTAssertEqual(monitor.activeIssues, [.blurry, .shaky])
        XCTAssertEqual(monitor.topIssue, .blurry)
    }

    func testResetClearsEverything() {
        let monitor = CaptureQualityMonitor()
        feed(blurry, times: 10, into: monitor)
        monitor.reset()
        XCTAssertTrue(monitor.activeIssues.isEmpty)
        XCTAssertFalse(monitor.hasSettled)
    }
}
