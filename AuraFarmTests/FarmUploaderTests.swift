import XCTest

@testable import AuraFarm

final class FarmUploaderTests: XCTestCase {
    private let farm = Farm(
        farmerName: "Pak Wayan",
        corners: [
            GeoPoint(latitude: -8.5, longitude: 115.1),
            GeoPoint(latitude: -8.5, longitude: 115.2),
            GeoPoint(latitude: -8.6, longitude: 115.2),
        ]
    )

    func testTheFarmColumnsAreNamedTheWayThePostgresTableIs() throws {
        let json = try encode(FarmRow(farm: farm))

        XCTAssertEqual(Set(json.keys), ["id", "name", "farmer_name"])
    }

    func testThePlotColumnsAreNamedTheWayThePostgresTableIs() throws {
        let boundary = PlotBoundary.wellKnownText(for: farm.corners) ?? ""

        let json = try encode(PlotRow(farm: farm, boundary: boundary))

        XCTAssertEqual(
            Set(json.keys), ["id", "farm_id", "plot_number", "boundary", "area_ha"])
    }

    func testThePlotKeepsTheFarmsIdSoPublishingTwiceDoesNotMakeASecondPlot() {
        let row = PlotRow(farm: farm, boundary: "SRID=4326;POLYGON((0 0, 1 0, 1 1, 0 0))")

        XCTAssertEqual(row.id, farm.id)
        XCTAssertEqual(row.farmID, farm.id)
        XCTAssertEqual(row.plotNumber, 1)
    }

    func testTheFarmsNameFallsBackToTheFarmersBecauseTheColumnCannotBeNull() {
        let row = FarmRow(farm: farm)

        XCTAssertEqual(row.name, "Pak Wayan")
        XCTAssertEqual(row.farmerName, "Pak Wayan")
    }

    private func encode(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
