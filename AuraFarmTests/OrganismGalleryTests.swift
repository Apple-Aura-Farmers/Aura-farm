import AuraFarmKit
import XCTest

@testable import AuraFarm

@MainActor
final class OrganismGalleryTests: XCTestCase {
    private func pictures(_ labels: [String]) -> [OrganismPicture] {
        labels.enumerated().map { index, label in
            OrganismPicture(
                image: SoilReport.OrganismImage(taxon: label, path: "t/\(index).jpg"),
                file: URL(filePath: "/t/\(index).jpg"))
        }
    }

    func testPicturesAreGroupedByNameWithTheMostFirst() {
        // Two labels with one name share a heading.
        let groups = OrganismGalleryScreen.groups(
            of: pictures(["amoeba", "nematode", "nematode", "Nematode"]))
        XCTAssertEqual(
            groups.map(\.name),
            [OrganismGalleryScreen.name(for: "nematode"), OrganismGalleryScreen.name(for: "amoeba")])
        XCTAssertEqual(groups.map(\.pictures.count), [3, 1])
        XCTAssertEqual(groups[0].pictures.map(\.file.lastPathComponent), ["1.jpg", "2.jpg", "3.jpg"])
    }

    func testTheNameIsTheDetailListsName() {
        let detail = SoilLifeGroup.summarize(["nematode": 1])[.nematodes]?.first?.organisms.first
        XCTAssertEqual(OrganismGalleryScreen.name(for: "nematode"), detail?.name)
    }

    func testALabelWithNoSoilLifeGroupKeepsTheRawLabel() {
        XCTAssertEqual(OrganismGalleryScreen.name(for: "an_unknown_class"), "an_unknown_class")
    }

    func testTheButtonIsHiddenWithNoPictures() {
        XCTAssertFalse(OrganismGalleryScreen.isOffered(for: []))
        XCTAssertTrue(OrganismGalleryScreen.isOffered(for: pictures(["nematode"])))
    }
}
