import XCTest

@testable import AuraFarm

final class SlideLabTestTests: XCTestCase {
    func testEveryTestHasATitleInstructionAndSlug() {
        for test in SlideLabTest.allCases {
            XCTAssertFalse(test.title.isEmpty)
            XCTAssertFalse(test.instruction.isEmpty)
            XCTAssertFalse(test.fileSlug.isEmpty)
            XCTAssertFalse(test.fileSlug.contains(" "))
        }
        XCTAssertEqual(SlideLabTest.dropSize.fileSlug, "drop-size")
        XCTAssertEqual(Set(SlideLabTest.allCases.map(\.fileSlug)).count, SlideLabTest.allCases.count)
    }
}
