import XCTest

@testable import AuraFarm

final class StageObjectiveTests: XCTestCase {
    func testDefaultChunks() {
        XCTAssertEqual(StageObjective.x40.defaultChunk, 3)
        XCTAssertEqual(StageObjective.x100.defaultChunk, 1)
        XCTAssertEqual(StageObjective.x40.title, "40x")
        XCTAssertEqual(StageObjective.x100.title, "100x")
    }

    func testNoWarningAtOrBelowRecommended() {
        for chunk in [1, 2, 3] { XCTAssertNil(StageObjective.x40.warning(forChunk: chunk)) }
        for chunk in [1, 2] { XCTAssertNil(StageObjective.x100.warning(forChunk: chunk)) }
    }

    func testWarningAboveRecommended() {
        for chunk in [5, 10] { XCTAssertNotNil(StageObjective.x40.warning(forChunk: chunk)) }
        for chunk in [3, 5, 10] { XCTAssertNotNil(StageObjective.x100.warning(forChunk: chunk)) }
    }
}
