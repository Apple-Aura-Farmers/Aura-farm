import XCTest

@testable import AuraFarm

final class SlideOrganismMapTests: XCTestCase {
    private let centre = CGPoint(x: 320, y: 240)

    /// A stationary organism: the content has moved by `position`, so it shows at `slide + position`.
    private func slide(seenAt frame: CGPoint, trackerPosition: CGPoint) -> CGPoint {
        SlideOrganismMap.slidePosition(
            boxCentre: frame, frameCentre: centre, trackerPosition: trackerPosition)
    }

    func testAStationaryOrganismMapsToTheSameSlidePointWhateverThePosition() {
        // Content moves right by 40 px (position +40): the organism shows 40 px further right.
        let first = slide(seenAt: CGPoint(x: 400, y: 200), trackerPosition: CGPoint(x: 10, y: 5))
        let second = slide(seenAt: CGPoint(x: 440, y: 200), trackerPosition: CGPoint(x: 50, y: 5))
        XCTAssertEqual(Double(first.x), Double(second.x), accuracy: 1e-9)
        XCTAssertEqual(Double(first.y), Double(second.y), accuracy: 1e-9)
    }

    func testAddingThePositionInsteadOfSubtractingItWouldNotHold() {
        let wrongFirst = 400 + 10.0
        let wrongSecond = 440 + 50.0
        XCTAssertNotEqual(wrongFirst, wrongSecond)
    }

    func testSameLabelWithinReachIsARepeatAndAnotherLabelIsNot() {
        var map = SlideOrganismMap()
        _ = map.add(label: "Volvox", at: CGPoint(x: 100, y: 100), seconds: 1, column: 1)
        XCTAssertNotNil(map.match(label: "Volvox", at: CGPoint(x: 120, y: 100), boxSide: 20))
        XCTAssertNil(map.match(label: "Volvox", at: CGPoint(x: 140, y: 100), boxSide: 20), "30 px minimum")
        XCTAssertNotNil(map.match(label: "Volvox", at: CGPoint(x: 150, y: 100), boxSide: 60), "one box side")
        XCTAssertNil(map.match(label: "Nematode", at: CGPoint(x: 100, y: 100), boxSide: 20))
        XCTAssertEqual(map.total, 1)
        XCTAssertEqual(map.countByLabel, ["Volvox": 1])
    }
}
