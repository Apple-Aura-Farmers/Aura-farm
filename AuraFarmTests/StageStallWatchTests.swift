import XCTest

@testable import AuraFarm

final class StageStallWatchTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1000)

    private func update(
        _ w: inout StageStallWatch, at s: Double, noDetail: Bool = true, hasDetail: Bool = false
    ) -> Bool {
        w.update(now: t0.addingTimeInterval(s), noDetail: noDetail, hasDetail: hasDetail)
    }

    func testFiresAfterTwoSecondsAndOnlyOncePerStretch() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertFalse(update(&w, at: 1.9))
        XCTAssertTrue(update(&w, at: 2.0))
        XCTAssertFalse(update(&w, at: 2.1))
        XCTAssertFalse(update(&w, at: 10))
    }

    func testMovesDoNotRestartTheCount() {
        // Moves are not an input: calling every 0.85 s, as the preset path does, still fires.
        var w = StageStallWatch()
        var fired = false
        for i in 0..<4 { fired = fired || update(&w, at: Double(i) * 0.85) }
        XCTAssertTrue(fired)
    }

    func testADetailFrameResetsTheCountAndTheStretch() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertFalse(update(&w, at: 1.5))
        XCTAssertFalse(update(&w, at: 1.6, noDetail: false, hasDetail: true))
        XCTAssertFalse(update(&w, at: 3.0))  // counting again from here
        XCTAssertTrue(update(&w, at: 5.0))
        // Detail again, then a new stretch fires again.
        XCTAssertFalse(update(&w, at: 6, noDetail: false, hasDetail: true))
        XCTAssertFalse(update(&w, at: 7))
        XCTAssertTrue(update(&w, at: 9))
    }

    func testAFrameThatIsNeitherLeavesTheCountAlone() {
        var w = StageStallWatch()
        XCTAssertFalse(update(&w, at: 0))
        XCTAssertFalse(update(&w, at: 1.0, noDetail: false))
        XCTAssertTrue(update(&w, at: 2.0))
    }

    func testSharpWhenFocusIsAtLeastEightyPercentOfBaselineElseBlurry() {
        let w = StageStallWatch()
        XCTAssertEqual(w.kind(focusIndex: 0.2, baseline: 0.25), .sharp)  // exactly 0.8
        XCTAssertEqual(w.kind(focusIndex: 0.3, baseline: 0.25), .sharp)
        XCTAssertEqual(w.kind(focusIndex: 0.19, baseline: 0.25), .blurry)
        XCTAssertEqual(w.kind(focusIndex: nil, baseline: 0.25), .blurry)
        XCTAssertEqual(w.kind(focusIndex: 0.2, baseline: nil), .blurry)
        XCTAssertEqual(w.kind(focusIndex: 0.2, baseline: 0), .blurry)
    }
}
