import XCTest

@testable import AuraFarm

/// Scripted sharpness at 10 readings a second.
final class FocusGuideTests: XCTestCase {
    private var guide = FocusGuide()
    private var seconds = 0.0
    private var readings: [FocusReading] = []
    private var noiseState: UInt64 = 11

    private func feed(_ values: [Double], noise: Double = 0, active: Int? = nil) {
        for value in values {
            seconds += 0.1
            var sharpness = value
            if noise > 0 {
                noiseState = noiseState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                sharpness *= 1 + noise * (Double(noiseState >> 33) / Double(1 << 31) - 1)
            }
            readings.append(guide.update(sharpness: sharpness, seconds: seconds, activeTiles: active))
        }
    }

    private func ramp(_ from: Double, _ to: Double, _ count: Int) -> [Double] {
        (1...count).map { from + (to - from) * Double($0) / Double(count) }
    }

    private var states: [FocusGuideState] { readings.map(\.state) }

    private func changes(from index: Int = 0) -> Int {
        zip(states.dropFirst(index), states.dropFirst(index + 1)).filter { $0 != $1 }.count
    }

    func testRiseThenFallPassesThePeak() {
        feed(ramp(50, 500, 40))
        XCTAssertTrue(states.allSatisfy { $0 == .turnOneWay })
        feed(ramp(500, 200, 20))
        XCTAssertEqual(states.last, .passedPeak)
        XCTAssertEqual(readings.last?.peak ?? 0, 500, accuracy: 20, "the median trails a ramp")
        XCTAssertLessThan(readings.last?.level ?? 1, 0.5)
    }

    func testBackNearThePeakIsNearThenFocusedAfterSettleSeconds() throws {
        feed(ramp(50, 500, 40) + ramp(500, 200, 20))
        feed(ramp(200, 475, 10) + [Double](repeating: 475, count: 25))
        let near = try XCTUnwrap(states.firstIndex(of: .nearPeak))
        let focused = try XCTUnwrap(states.firstIndex(of: .focused))
        XCTAssertGreaterThanOrEqual(focused - near, 6, "after settleSeconds, not at once")
        XCTAssertLessThanOrEqual(focused - near, 14)
        XCTAssertEqual(states.last, .focused)
        feed([100, 50, 480], noise: 0)
        XCTAssertEqual(states.last, .focused, "focused stays")
    }

    func testFlatAndLowForTwelveSecondsNeedsSampleAndRecovers() {
        feed([Double](repeating: 80, count: 130))
        XCTAssertEqual(states.last, .needsSample)
        XCTAssertFalse(states.prefix(120).contains(.needsSample), "not before the 12 s")
        feed(ramp(80, 400, 10))
        XCTAssertEqual(states.last, .turnOneWay)
    }

    func testASparseViewThatPeaksLowIsAccepted() {
        feed(ramp(20, 110, 30) + ramp(110, 30, 20) + ramp(30, 100, 10))
        feed([Double](repeating: 100, count: 20))
        XCTAssertEqual(states.last, .focused)
    }

    func testAnEmptyViewThatHardlyChangesIsNot() {
        feed(ramp(50, 65, 40) + ramp(65, 50, 40) + ramp(50, 65, 40))
        feed([Double](repeating: 55, count: 20))
        XCTAssertEqual(states.last, .needsSample)
    }

    // MARK: Too little sample (the tiles' active count)

    func testFewActiveTilesForTwelveSecondsNeedsSample() {
        feed([Double](repeating: 80, count: 130), active: 7)
        XCTAssertEqual(states.last, .needsSample)
        XCTAssertFalse(states.prefix(120).contains(.needsSample))
    }

    func testEightActiveTilesKeepTurnOneWayEvenWithALowPeak() {
        feed([Double](repeating: 80, count: 300), active: 8)
        XCTAssertTrue(states.allSatisfy { $0 == .turnOneWay }, "a low peak alone is not too little sample")
    }

    func testNeedsSampleClearsAsSoonAsATilesReadingHasEightActive() {
        feed([Double](repeating: 80, count: 130), active: 3)
        XCTAssertEqual(states.last, .needsSample)
        feed([80], active: 8)
        XCTAssertEqual(states.last, .turnOneWay)
        feed([Double](repeating: 80, count: 50))
        XCTAssertEqual(states.last, .turnOneWay, "the spot has shown enough")
    }

    func testFramesWithoutAReadingDoNotChangeTheCount() {
        feed([Double](repeating: 80, count: 60), active: 3)
        feed([Double](repeating: 80, count: 55))
        XCTAssertFalse(states.contains(.needsSample), "11.5 s at this spot")
        feed([Double](repeating: 80, count: 15))
        XCTAssertEqual(states.last, .needsSample)
    }

    func testASpotThatShowedEnoughNeverNeedsSampleWhenTheKnobIsTurnedAway() {
        feed([Double](repeating: 80, count: 5), active: 9)
        feed([Double](repeating: 80, count: 300), active: 2)
        XCTAssertFalse(states.contains(.needsSample))
        guide.reset()
        feed([Double](repeating: 80, count: 130), active: 2)
        XCTAssertEqual(states.last, .needsSample, "a new spot starts afresh")
    }

    func testOneShakeDoesNotSetAPeakThatCannotBeReached() {
        feed(ramp(50, 500, 40) + [5000] + ramp(500, 200, 20) + ramp(200, 480, 10))
        feed([Double](repeating: 480, count: 20))
        XCTAssertEqual(states.last, .focused)
    }

    func testNoisyReadingsAroundAPeakStillEndFocusedWithoutFlipping() {
        feed(ramp(50, 500, 40) + ramp(500, 250, 20) + ramp(250, 500, 20), noise: 0.1)
        feed([Double](repeating: 500, count: 100), noise: 0.1)
        XCTAssertEqual(states.last, .focused)
        XCTAssertLessThanOrEqual(changes(), 6, "\(states.map(\.csvName))")
    }

    func testOvershootingTwiceStillEndsFocused() {
        feed(ramp(50, 500, 40))
        feed(ramp(500, 200, 15))  // passed the peak
        feed(ramp(200, 380, 10))  // back, not near yet
        feed(ramp(380, 150, 15))  // passed again
        feed(ramp(150, 480, 15))  // back, near
        feed(ramp(480, 250, 8))  // overshoots once more
        feed(ramp(250, 495, 12))
        feed([Double](repeating: 495, count: 25))
        XCTAssertEqual(states.last, .focused)
        XCTAssertEqual(states.filter { $0 == .passedPeak }.isEmpty, false)
    }

    func testANewPeakInNearPeakJustRaisesThePeak() {
        feed(ramp(50, 500, 40) + ramp(500, 200, 20) + ramp(200, 470, 10))
        feed([470, 470])
        XCTAssertEqual(states.last, .nearPeak)
        let before = readings.last?.peak ?? 0
        feed(ramp(470, 540, 5) + [540, 540])
        XCTAssertNotEqual(states.last, .passedPeak)
        XCTAssertGreaterThan(readings.last?.peak ?? 0, before + 20, "the peak was raised")
    }
}
