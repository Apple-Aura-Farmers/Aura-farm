import CoreGraphics
import XCTest

@testable import MicroscopeCounter

final class DetectorTests: XCTestCase {
    func testABoxCoveringTheWholeFrameIsNotAFind() {
        // What the nineteen-class weights produced on real footage: a box the size of the
        // picture, and sometimes a little larger than it.
        XCTAssertTrue(Detector.coversWholeFrame(CGRect(x: 0, y: 0, width: 1, height: 1)))
        XCTAssertTrue(Detector.coversWholeFrame(CGRect(x: -0.02, y: -0.02, width: 1.04, height: 1.04)))
    }

    func testABoxOnSomethingInTheFrameIsKept() {
        // Boxes on organisms measured 1% to 9% of the frame.
        XCTAssertFalse(Detector.coversWholeFrame(CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.3)))
        XCTAssertFalse(Detector.coversWholeFrame(CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)))
    }

    func testALongThinBoxAcrossTheFrameIsStillAFind() {
        // A nematode lying across the view is wide but not tall, so area is the right test
        // rather than either side on its own.
        XCTAssertFalse(Detector.coversWholeFrame(CGRect(x: 0, y: 0.45, width: 1, height: 0.1)))
    }
}

final class DetectVideoViewTests: XCTestCase {
    func testAPictureIsFittedToTheShapeOfTheSheet() {
        // A 1920x1080 frame in a tall sheet fills the width and leaves the height short, so
        // zooming in walks across the picture rather than into empty space beside it.
        let fitted = DetectVideoView.sizeFitting(
            CGSize(width: 1920, height: 1080), in: CGSize(width: 400, height: 800))
        XCTAssertEqual(fitted.width, 400, accuracy: 0.01)
        XCTAssertEqual(fitted.height, 225, accuracy: 0.01)
    }

    func testAPictureWithNoSizeFallsBackToTheSheet() {
        let bounds = CGSize(width: 400, height: 800)
        XCTAssertEqual(DetectVideoView.sizeFitting(.zero, in: bounds), bounds)
    }
}
