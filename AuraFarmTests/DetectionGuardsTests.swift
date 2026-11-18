import XCTest

@testable import AuraFarm

final class DetectionGuardsTests: XCTestCase {
    private let frame = CGSize(width: 1280, height: 720)
    /// The eyepiece circle measured on the fixture frames, and the square the guards compare with.
    private let circle = FieldCircle(centre: CGPoint(x: 745, y: 412), radius: 253)
    private let guards = DetectionGuards()

    private func box(centre: CGPoint, width: Double, height: Double) -> CGRect {
        CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
    }

    func testTheDiscSizedBoxIsDroppedWithoutACrop() {
        // The V2 box on the disc: about 0.47 x 0.77 of the frame.
        let disc = box(centre: CGPoint(x: 745, y: 412), width: 0.465 * 1280, height: 0.77 * 720)
        XCTAssertEqual(guards.drop(box: disc, crop: nil, circle: circle), .disc)
    }

    func testABigBoxIsDroppedWithACropAndASmallOneIsKept() {
        let crop = FieldCentring.cropRect(for: circle, frameSize: frame)
        let big = box(centre: crop.mid, width: 0.7 * crop.width, height: 0.9 * crop.height)
        XCTAssertEqual(guards.drop(box: big, crop: crop, circle: circle), .big)
        let small = box(centre: crop.mid, width: 0.07 * crop.width, height: 0.06 * crop.height)
        XCTAssertNil(guards.drop(box: small, crop: crop, circle: circle))
        XCTAssertNil(guards.drop(box: small, crop: nil, circle: circle))
    }

    func testWithoutACropOrACircleNothingIsDropped() {
        let big = box(centre: CGPoint(x: 600, y: 360), width: 900, height: 600)
        XCTAssertNil(guards.drop(box: big, crop: nil, circle: nil))
    }

    func testTheCounterDropsAndCountsThem() {
        var counter = LiveOrganismCounter()
        let crop = FieldCentring.cropRect(for: circle, frameSize: frame)
        func share(_ rect: CGRect) -> CGRect {
            CGRect(
                x: rect.minX / 1280, y: 1 - rect.maxY / 720, width: rect.width / 1280,
                height: rect.height / 720)
        }
        let big = share(box(centre: crop.mid, width: 0.7 * crop.width, height: 0.9 * crop.height))
        let small = share(box(centre: crop.mid, width: 40, height: 40))
        let result = counter.update(
            detections: [
                OrganismDetector.Detection(label: "Volvox", confidence: 0.8, box: big),
                OrganismDetector.Detection(label: "Stentor", confidence: 0.8, box: small),
            ], pictureMoved: .zero, trackerPosition: .zero, frameSize: frame, fieldCircle: circle,
            crop: crop, seconds: 0, column: 1)
        XCTAssertEqual(result.droppedBig, 1)
        XCTAssertEqual(result.found, 1)
        XCTAssertEqual(counter.bigDrops, 1)
    }

    func testTheCapturePathsWholeFrameGuardIsUnchanged() {
        XCTAssertTrue(OrganismDetector.coversWholeFrame(CGRect(x: 0, y: 0, width: 0.95, height: 0.95)))
        XCTAssertFalse(OrganismDetector.coversWholeFrame(CGRect(x: 0, y: 0, width: 0.7, height: 0.7)))
        XCTAssertEqual(OrganismDetector.largestBoxShare, 0.8)
    }
}

extension CGRect {
    fileprivate var mid: CGPoint { CGPoint(x: midX, y: midY) }
}
