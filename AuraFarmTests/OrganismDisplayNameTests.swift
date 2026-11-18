import XCTest

@testable import AuraFarm

final class OrganismDisplayNameTests: XCTestCase {
    func testUnderscoresBecomeSlashes() {
        XCTAssertEqual(
            OrganismDisplayName.label("Didinium_Phacus_Collodictyon"), "Didinium / Phacus / Collodictyon")
        XCTAssertEqual(OrganismDisplayName.label("Paramecium_Coleps"), "Paramecium / Coleps")
    }

    func testOtherLabelsAreUnchanged() {
        XCTAssertEqual(OrganismDisplayName.label("Volvox"), "Volvox")
        XCTAssertEqual(OrganismDisplayName.label(""), "")
    }

    func testTheRawLabelStaysTheDataInTheCounter() {
        var counter = LiveOrganismCounter()
        let found = OrganismDetector.Detection(
            label: "Paramecium_Coleps", confidence: 0.9,
            box: CGRect(x: 0.4, y: 0.4, width: 0.05, height: 0.05))
        for _ in 0..<3 {
            counter.update(
                detections: [found], pictureMoved: .zero, trackerPosition: .zero,
                frameSize: CGSize(width: 1000, height: 1000), fieldCircle: nil, seconds: 0, column: 1)
        }
        XCTAssertEqual(counter.helperCountByLabel, ["Paramecium_Coleps": 1])
    }
}
