import XCTest

@testable import AuraFarm

final class StagePresetEdgeWatchTests: XCTestCase {
    private var watch = StagePresetEdgeWatch()

    /// One stop: what the view showed during it.
    private func stop(sample: Bool = false, blank: Bool = false) -> Bool {
        watch.beginStop()
        watch.observe(isSample: sample, isBlank: blank)
        return watch.endStop()
    }

    func testTwoBlankStopsDoNotEndAColumnButThreeDo() {
        XCTAssertFalse(stop(sample: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertTrue(stop(blank: true))
    }

    func testBlurryNeverCountsAndBreaksTheRow() {
        XCTAssertFalse(stop(sample: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(), "a blurry stop is not blank")
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertTrue(stop(blank: true))
    }

    func testASampleViewResetsTheCount() {
        XCTAssertFalse(stop(sample: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(sample: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertTrue(stop(blank: true))
    }

    func testAStopIsBlankOnlyIfItWasBlankForItsWholeDwell() {
        XCTAssertFalse(stop(sample: true))
        watch.beginStop()
        watch.observe(isSample: false, isBlank: true)
        watch.observe(isSample: false, isBlank: false)
        XCTAssertFalse(watch.endStop())
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertTrue(stop(blank: true))
    }

    func testAColumnThatNeverShowedSampleNeverEnds() {
        for _ in 0..<20 { XCTAssertFalse(stop(blank: true)) }
    }

    func testANewColumnStartsAgain() {
        XCTAssertFalse(stop(sample: true))
        XCTAssertFalse(stop(blank: true))
        watch.newColumn()
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true))
        XCTAssertFalse(stop(blank: true), "no sample in this column yet")
    }
}
