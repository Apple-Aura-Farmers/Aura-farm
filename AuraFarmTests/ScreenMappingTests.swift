import XCTest

@testable import AuraFarm

final class ScreenMappingTests: XCTestCase {
    func testRotationsOfARightwardMove() {
        let right = CGPoint(x: 1, y: 0)
        XCTAssertEqual(ScreenMapping.asIs.onScreen(right, mirrored: false), CGPoint(x: 1, y: 0))
        // Clockwise: right becomes down (y grows downward on screen).
        XCTAssertEqual(ScreenMapping.rotateRight.onScreen(right, mirrored: false), CGPoint(x: 0, y: 1))
        XCTAssertEqual(ScreenMapping.rotateLeft.onScreen(right, mirrored: false), CGPoint(x: 0, y: -1))
        XCTAssertEqual(ScreenMapping.rotate180.onScreen(right, mirrored: false), CGPoint(x: -1, y: 0))
    }

    func testRotatingFourTimesIsTheIdentity() {
        let down = CGPoint(x: 0, y: 1)
        var vector = down
        for _ in 0..<4 { vector = ScreenMapping.rotateRight.onScreen(vector, mirrored: false) }
        XCTAssertEqual(vector, down)
    }

    func testMirrorFlipsTheHorizontalAfterRotating() {
        XCTAssertEqual(
            ScreenMapping.asIs.onScreen(CGPoint(x: 2, y: 3), mirrored: true), CGPoint(x: -2, y: 3))
        // Right, rotated right, is down; the mirror leaves a vertical move alone.
        XCTAssertEqual(
            ScreenMapping.rotateRight.onScreen(CGPoint(x: 1, y: 0), mirrored: true),
            CGPoint(x: 0, y: 1))
    }
}
