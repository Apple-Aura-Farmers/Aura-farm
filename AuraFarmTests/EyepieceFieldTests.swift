import XCTest

@testable import AuraFarm

final class EyepieceFieldTests: XCTestCase {
    func testTheCentreSquareIsCentredAndInWholePixels() {
        let square = EyepieceField.centreSquare(frameSize: CGSize(width: 1280, height: 720))
        XCTAssertEqual(square, CGRect(x: 388, y: 108, width: 504, height: 504))
    }

    func testTheCentreSquareStaysInsideAnyFrame() {
        for size in [CGSize(width: 322, height: 243), CGSize(width: 100, height: 100)] {
            let square = EyepieceField.centreSquare(frameSize: size)
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(square))
            XCTAssertEqual(square.minX, square.minX.rounded())
        }
    }

    func testVisionRegionFlipsTheVertical() {
        let size = CGSize(width: 1000, height: 500)
        let topLeft = CGRect(x: 0, y: 0, width: 250, height: 100)
        let region = EyepieceField.visionRegion(of: topLeft, frameSize: size)
        XCTAssertEqual(region.minX, 0, accuracy: 0.0001)
        XCTAssertEqual(region.minY, 0.8, accuracy: 0.0001, "top of the frame is a high y")
        XCTAssertEqual(region.width, 0.25, accuracy: 0.0001)
        XCTAssertEqual(region.height, 0.2, accuracy: 0.0001)

        let bottomRight = CGRect(x: 750, y: 400, width: 250, height: 100)
        XCTAssertEqual(
            EyepieceField.visionRegion(of: bottomRight, frameSize: size).minY, 0, accuracy: 0.0001)
    }
}
