import XCTest

@testable import AuraFarm

final class StageStallWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    private func update(
        _ w: inout StageStallWatch, at s: Double, holds: Bool = true, moved: Bool = false,
        index: Double? = 0.1, baseline: Double? = 0.21
    ) -> Bool {
        w.update(
            now: t0.addingTimeInterval(s), holds: holds, moved: moved, focusIndex: index,
            baseline: baseline)
    }

    func testFiresOnceAfterHold() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertFalse(update(&w, at: 2.9))
        XCTAssertTrue(update(&w, at: 3.0))
        XCTAssertFalse(update(&w, at: 6.0))
    }

    func testNeedsLowFocus() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0, index: 0.2))
        XCTAssertFalse(update(&w, at: 4, index: 0.2))
        XCTAssertFalse(update(&w, at: 5, index: nil))
        XCTAssertTrue(update(&w, at: 6, index: 0.1))
    }

    func testMoveRestartsWindow() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertFalse(update(&w, at: 2.5, moved: true))
        XCTAssertFalse(update(&w, at: 5.0))
        XCTAssertTrue(update(&w, at: 5.5))
    }

    func testNewStallNeedsHoldToDrop() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertTrue(update(&w, at: 3))
        XCTAssertFalse(update(&w, at: 4, holds: false))
        XCTAssertFalse(update(&w, at: 5))
        XCTAssertTrue(update(&w, at: 8))
    }

    func testLongStallFiresWithGoodFocus() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0, index: 0.2))
        XCTAssertFalse(update(&w, at: 5.9, index: 0.2))
        XCTAssertTrue(update(&w, at: 6.0, index: 0.2))
        XCTAssertFalse(update(&w, at: 9.0, index: 0.2))
    }

    func testLongStallFiresWithoutFocusNumbers() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0, index: nil, baseline: nil))
        XCTAssertFalse(update(&w, at: 5.9, index: nil, baseline: nil))
        XCTAssertTrue(update(&w, at: 6.0, index: nil, baseline: nil))
        XCTAssertFalse(update(&w, at: 12.0, index: nil, baseline: nil))
        // A new stall needs holds to drop first.
        XCTAssertFalse(update(&w, at: 13, holds: false))
        XCTAssertFalse(update(&w, at: 14, index: nil, baseline: nil))
        XCTAssertTrue(update(&w, at: 20, index: nil, baseline: nil))
    }
}
