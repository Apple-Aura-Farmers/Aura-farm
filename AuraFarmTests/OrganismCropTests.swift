import XCTest

@testable import AuraFarm

final class OrganismCropTests: XCTestCase {
    private let frame = CGSize(width: 1920, height: 1080)

    func testTheBoxGetsHalfItsSizeOnEachSideAndIsSquared() {
        // 100 x 60 grows to 200 x 120 (the margin on each side); squared on the longer side.
        let crop = OrganismCrop.rect(box: CGRect(x: 900, y: 500, width: 100, height: 60), frame: frame)
        XCTAssertEqual(crop.width, 200)
        XCTAssertEqual(crop.height, 200)
        XCTAssertEqual(crop.midX, 950, accuracy: 1)
        XCTAssertEqual(crop.midY, 530, accuracy: 1)
    }

    func testTheCropIsShiftedInsideTheFrameAtEachEdge() {
        let topLeft = OrganismCrop.rect(box: CGRect(x: 0, y: 0, width: 100, height: 100), frame: frame)
        XCTAssertEqual(topLeft, CGRect(x: 0, y: 0, width: 200, height: 200))
        let bottomRight = OrganismCrop.rect(
            box: CGRect(x: 1850, y: 1010, width: 70, height: 70), frame: frame)
        XCTAssertEqual(bottomRight.maxX, 1920)
        XCTAssertEqual(bottomRight.maxY, 1080)
        XCTAssertEqual(bottomRight.width, 140)
    }

    func testABoxBiggerThanTheFrameIsKeptToTheFramesShortSide() {
        let crop = OrganismCrop.rect(box: CGRect(x: 100, y: 100, width: 900, height: 900), frame: frame)
        XCTAssertEqual(crop.width, 1080)
        XCTAssertEqual(crop.height, 1080)
        XCTAssertGreaterThanOrEqual(crop.minX, 0)
        XCTAssertLessThanOrEqual(crop.maxX, 1920)
    }

    func testTheSavedSideIsAtMost384AndNeverEnlarged() {
        XCTAssertEqual(OrganismCrop.outputSide(for: 1000), 384)
        XCTAssertEqual(OrganismCrop.outputSide(for: 384), 384)
        XCTAssertEqual(OrganismCrop.outputSide(for: 200), 200)
    }
}
