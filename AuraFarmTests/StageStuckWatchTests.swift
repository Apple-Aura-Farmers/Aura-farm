import XCTest

@testable import AuraFarm

final class StageStuckWatchTests: XCTestCase {
    /// A judged move: detail before and after, 0.4 field expected, `seen` travelled.
    private func move(
        _ w: inout StageStuckWatch, servo: StageAxis = .x, seen: Double,
        expected: Double = 0.4, before: Bool = true, after: Bool = true
    ) -> StageStuckWatch.Outcome {
        w.record(
            servo: servo, seen: seen, expected: expected, detailBefore: before, detailAfter: after)
    }

    func testThreeNoResponseMovesInARowBoostThatServo() {
        var w = StageStuckWatch()
        XCTAssertTrue(move(&w, seen: 0.01).noResponse)
        XCTAssertTrue(move(&w, seen: 0.0).noResponse)
        XCTAssertEqual(w.extraDegrees(for: .x), 0)
        let third = move(&w, seen: 0.02)
        XCTAssertTrue(third.boostOn)
        XCTAssertEqual(w.extraDegrees(for: .x), 2)
        XCTAssertEqual(w.extraDegrees(for: .y), 0, "only that servo")
    }

    func testAnAnswerInTheMiddleBreaksTheRow() {
        var w = StageStuckWatch()
        _ = move(&w, seen: 0.0)
        _ = move(&w, seen: 0.0)
        _ = move(&w, seen: 0.15)  // 37%: not no-response, not clearly moved
        XCTAssertFalse(move(&w, seen: 0.0).boostOn)
        XCTAssertEqual(w.extraDegrees(for: .x), 0)
    }

    func testAMovingMoveEndsTheBoost() {
        var w = StageStuckWatch()
        for _ in 0..<3 { _ = move(&w, seen: 0) }
        XCTAssertEqual(w.extraDegrees(for: .x), 2)
        // 30% is an answer but not a clear one: the boost stays.
        XCTAssertNil(move(&w, seen: 0.12).boostOff)
        XCTAssertEqual(w.extraDegrees(for: .x), 2)
        let moved = move(&w, seen: 0.25)  // 62%
        XCTAssertEqual(moved.boostOff, .moved)
        XCTAssertEqual(w.extraDegrees(for: .x), 0)
    }

    func testFiveBoostedNoResponseMovesGiveUp() {
        var w = StageStuckWatch()
        for _ in 0..<3 { _ = move(&w, seen: 0) }
        for i in 1...4 {
            XCTAssertNil(move(&w, seen: 0).boostOff, "boosted miss \(i)")
        }
        XCTAssertEqual(move(&w, seen: 0).boostOff, .gaveUp)
        XCTAssertEqual(w.extraDegrees(for: .x), 0)
        // Back to normal: three more misses are needed to boost again.
        XCTAssertFalse(move(&w, seen: 0).boostOn)
    }

    func testMovesWithoutDetailOrWithTinyExpectedTravelAreNotJudged() {
        var w = StageStuckWatch()
        for _ in 0..<5 {
            XCTAssertFalse(move(&w, seen: 0, before: false).judged)
            XCTAssertFalse(move(&w, seen: 0, after: false).judged)
            XCTAssertFalse(move(&w, seen: 0, expected: 0.09).judged)
        }
        XCTAssertEqual(w.extraDegrees(for: .x), 0)
        XCTAssertTrue(move(&w, seen: 0, expected: 0.1).judged)
    }
}
