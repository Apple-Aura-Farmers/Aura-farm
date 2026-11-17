import XCTest

@testable import AuraFarm

final class ThrottleTests: XCTestCase {
    func testTenUpdatesInOneSecondPassAtMostFive() {
        var throttle = Throttle<Int>(interval: 0.25)
        var sent: [Int] = []
        for index in 0..<10 {
            if let value = throttle.offer(index, at: Double(index) * 0.1) { sent.append(value) }
        }
        XCTAssertLessThanOrEqual(sent.count, 5, "leading plus 4 a second: \(sent)")
        XCTAssertEqual(sent.first, 0, "the first goes at once")
    }

    func testTheLastValueAlwaysArrives() {
        var throttle = Throttle<Int>(interval: 0.25)
        _ = throttle.offer(1, at: 0)
        XCTAssertNil(throttle.offer(2, at: 0.05))
        XCTAssertNil(throttle.offer(3, at: 0.10), "kept as the pending one")
        XCTAssertNil(throttle.takePending(at: 0.20), "not due yet")
        XCTAssertEqual(throttle.secondsUntilDue(at: 0.10) ?? -1, 0.15, accuracy: 1e-9)
        XCTAssertEqual(throttle.takePending(at: 0.25), 3, "the newest, once due")
        XCTAssertNil(throttle.takePending(at: 0.60), "sent once")
    }

    func testAnUpdateAfterAQuietGapGoesThroughAtOnce() {
        var throttle = Throttle<String>(interval: 0.25)
        _ = throttle.offer("a", at: 0)
        XCTAssertEqual(throttle.offer("b", at: 5), "b")
        XCTAssertNil(throttle.pending)
    }

    func testForceSendsAtOnceAndFlushGivesThePendingOne() {
        var throttle = Throttle<Int>(interval: 0.25)
        _ = throttle.offer(1, at: 0)
        XCTAssertEqual(throttle.offer(2, at: 0.01, force: true), 2)
        XCTAssertNil(throttle.offer(3, at: 0.02))
        XCTAssertEqual(throttle.flush(), 3)
        XCTAssertNil(throttle.flush())
    }

    func testTheDefaultIsFourUpdatesASecond() {
        XCTAssertEqual(ScreenUpdateThresholds().interval, 0.25, accuracy: 1e-9)
    }

    /// The main-queue wrapper: a burst delivers the first value now and the last one later.
    func testMainThrottleEndsOnTheLatestValue() {
        let delivered = expectation(description: "the last value arrives")
        var received: [Int] = []
        let throttle = MainThrottle<Int>(interval: 0.1) { value in
            received.append(value)
            if value == 9 { delivered.fulfill() }
        }
        for value in 0..<10 { throttle.offer(value) }
        wait(for: [delivered], timeout: 2)
        XCTAssertEqual(received.first, 0)
        XCTAssertEqual(received.last, 9)
        XCTAssertLessThanOrEqual(received.count, 3)
    }
}
