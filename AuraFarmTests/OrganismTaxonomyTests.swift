import AuraFarmKit
import XCTest

@testable import AuraFarm

final class OrganismTaxonomyTests: XCTestCase {
    func testModelClassesAreListedMostCountedFirstWithoutZeroes() {
        let rows = OrganismTaxonomy.modelClass.rows(from: ["euglena": 3, "paramecium": 9, "volvox": 0])

        XCTAssertEqual(rows.map(\.label), ["paramecium", "euglena"])
        XCTAssertEqual(rows.map(\.count), [9, 3])
    }

    func testGroupsSumTheirMappedClassesAndCollectTheRest() {
        let rows = OrganismTaxonomy.organismGroup.rows(
            from: ["paramecium": 5, "stentor": 2, "vorticella": 1, "euglena": 4, "volvox": 3]
        )

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].label, OrganismGroup.hypotrichida.rawValue)
        XCTAssertEqual(rows[0].count, 8)
        XCTAssertEqual(rows[1].name, OrganismTaxonomy.unmappedName)
        XCTAssertNil(rows[1].label)
        XCTAssertEqual(rows[1].count, 7)
    }

    func testNoUnmappedRowWhenEverythingMaps() {
        let rows = OrganismTaxonomy.organismGroup.rows(from: ["paramecium": 5])

        XCTAssertEqual(rows.map(\.name), [OrganismGroup.hypotrichida.commonName])
    }

    func testALabelNamedAfterAGroupIsThatGroup() {
        let rows = OrganismTaxonomy.organismGroup.rows(from: ["Nematoda": 4])

        XCTAssertEqual(rows.first?.label, "Nematoda")
    }

    func testTheMappingCanBeChangedWithoutTouchingTheRows() {
        var mapping = ProvisionalTaxonMapping()
        mapping.table["euglena"] = .arcellinida

        let rows = OrganismTaxonomy.organismGroup.rows(from: ["euglena": 4], mapping: mapping)

        XCTAssertEqual(rows.first?.label, OrganismGroup.arcellinida.rawValue)
    }
}
