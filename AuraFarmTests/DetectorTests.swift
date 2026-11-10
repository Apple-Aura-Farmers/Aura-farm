import CoreGraphics
import CoreML
import XCTest

@testable import AuraFarm

final class DetectorTests: XCTestCase {
    func testAQueryIsReadAsTheBestClassThatIsNotNoObject() throws {
        // Three queries: one a nematode, one the model saying it found nothing, one a
        // volvox so small the guard leaves it alone.
        let (logits, boxes) = try queries([
            (slot: 4, logit: 3.0, box: (0.5, 0.5, 0.2, 0.1)),
            (slot: 0, logit: 5.0, box: (0.5, 0.5, 0.9, 0.9)),
            (slot: 5, logit: 2.0, box: (0.25, 0.25, 0.1, 0.1)),
        ])

        let found = OrganismDetector.decode(logits: logits, boxes: boxes)

        XCTAssertEqual(found.map(\.label), ["Nematode", "Volvox"])
        // Boxes come in as the middle and the size counted from the top left; everything
        // downstream counts from the bottom left.
        let nematode = try XCTUnwrap(found.first)
        XCTAssertEqual(nematode.box.minX, 0.4, accuracy: 0.001)
        XCTAssertEqual(nematode.box.minY, 0.45, accuracy: 0.001)
        XCTAssertEqual(nematode.box.width, 0.2, accuracy: 0.001)
    }

    func testAQuietQueryIsNotAFind() throws {
        // Well under leastConfidence once it has been through a sigmoid.
        let (logits, boxes) = try queries([(slot: 4, logit: -3.0, box: (0.5, 0.5, 0.1, 0.1))])
        XCTAssertTrue(OrganismDetector.decode(logits: logits, boxes: boxes).isEmpty)
    }

    func testAQueryBoxingTheWholeFrameIsStillThrownAway() throws {
        let (logits, boxes) = try queries([(slot: 4, logit: 5.0, box: (0.5, 0.5, 1.0, 1.0))])
        XCTAssertTrue(OrganismDetector.decode(logits: logits, boxes: boxes).isEmpty)
    }

    /// Builds the two tensors the model hands back, one row per query.
    private func queries(
        _ rows: [(slot: Int, logit: Float, box: (Double, Double, Double, Double))]
    ) throws -> (MLMultiArray, MLMultiArray) {
        let classes = OrganismDetector.classNames.count
        let logits = try MLMultiArray(
            shape: [1, NSNumber(value: rows.count), NSNumber(value: classes)], dataType: .float32)
        let boxes = try MLMultiArray(shape: [1, NSNumber(value: rows.count), 4], dataType: .float32)
        for (query, row) in rows.enumerated() {
            for klass in 0..<classes {
                logits[[0, NSNumber(value: query), NSNumber(value: klass)]] =
                    NSNumber(value: klass == row.slot ? row.logit : -10)
            }
            let values = [row.box.0, row.box.1, row.box.2, row.box.3]
            for (index, value) in values.enumerated() {
                boxes[[0, NSNumber(value: query), NSNumber(value: index)]] = NSNumber(value: value)
            }
        }
        return (logits, boxes)
    }

    func testABoxCoveringTheWholeFrameIsNotAFind() {
        // What the nineteen-class weights produced on real footage: a box the size of the
        // picture, and sometimes a little larger than it.
        XCTAssertTrue(OrganismDetector.coversWholeFrame(CGRect(x: 0, y: 0, width: 1, height: 1)))
        XCTAssertTrue(
            OrganismDetector.coversWholeFrame(CGRect(x: -0.02, y: -0.02, width: 1.04, height: 1.04))
        )
    }

    func testABoxOnSomethingInTheFrameIsKept() {
        // Boxes on organisms measured 1% to 9% of the frame.
        XCTAssertFalse(OrganismDetector.coversWholeFrame(CGRect(x: 0.4, y: 0.4, width: 0.3, height: 0.3)))
        XCTAssertFalse(OrganismDetector.coversWholeFrame(CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05)))
    }

    func testALongThinBoxAcrossTheFrameIsStillAFind() {
        // A nematode lying across the view is wide but not tall, so area is the right test
        // rather than either side on its own.
        XCTAssertFalse(OrganismDetector.coversWholeFrame(CGRect(x: 0, y: 0.45, width: 1, height: 0.1)))
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
