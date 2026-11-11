import XCTest

@testable import AuraFarm

final class PreviewGeometryTests: XCTestCase {
    func testAsIsFillingTheSameShape() {
        let rect = PreviewGeometry.rect(
            of: CGRect(x: 100, y: 50, width: 200, height: 100),
            frameSize: CGSize(width: 1280, height: 720), viewSize: CGSize(width: 640, height: 360),
            mapping: .asIs, mirrored: false)
        XCTAssertEqual(rect.minX, 50, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 25, accuracy: 0.001)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
    }

    func testRotatingRightMovesTopLeftToTopRight() {
        let rect = PreviewGeometry.rect(
            of: CGRect(x: 0, y: 0, width: 10, height: 10),
            frameSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 50, height: 100),
            mapping: .rotateRight, mirrored: false)
        XCTAssertEqual(rect.minX, 40, accuracy: 0.001)
        XCTAssertEqual(rect.maxX, 50, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 0, accuracy: 0.001)
        XCTAssertEqual(rect.maxY, 10, accuracy: 0.001)
    }

    func testAspectFillCropsTheLongSide() {
        // A 100x50 frame shown upright (rotated) in a 50x50 view: scaled by 1 (fill), centred.
        let rect = PreviewGeometry.rect(
            of: CGRect(x: 0, y: 0, width: 100, height: 50),
            frameSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 50, height: 50),
            mapping: .asIs, mirrored: false)
        XCTAssertEqual(rect.width, 100, accuracy: 0.001)
        XCTAssertEqual(rect.midX, 25, accuracy: 0.001)
    }

    func testMirrorFlipsHorizontally() {
        let rect = PreviewGeometry.rect(
            of: CGRect(x: 0, y: 0, width: 10, height: 10),
            frameSize: CGSize(width: 100, height: 100), viewSize: CGSize(width: 100, height: 100),
            mapping: .asIs, mirrored: true)
        XCTAssertEqual(rect.minX, 90, accuracy: 0.001)
    }

    func testTheTransformPlacesPointsLikeTheRect() {
        let transform = PreviewGeometry.transform(
            frameSize: CGSize(width: 100, height: 50), viewSize: CGSize(width: 50, height: 100),
            mapping: .rotateRight, mirrored: false)
        let corner = CGPoint(x: 0, y: 0).applying(transform)
        XCTAssertEqual(corner.x, 50, accuracy: 0.001)
        XCTAssertEqual(corner.y, 0, accuracy: 0.001)
        let inner = CGPoint(x: 10, y: 10).applying(transform)
        XCTAssertEqual(inner.x, 40, accuracy: 0.001)
        XCTAssertEqual(inner.y, 10, accuracy: 0.001)
    }
}
