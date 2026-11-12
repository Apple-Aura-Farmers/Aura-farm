import XCTest

@testable import AuraFarm

final class FarmUploaderTests: XCTestCase {
    private let plot = Plot(corners: [
        GeoPoint(latitude: -8.5, longitude: 115.1),
        GeoPoint(latitude: -8.5, longitude: 115.2),
        GeoPoint(latitude: -8.6, longitude: 115.2),
    ])
    private lazy var farm = Farm(
        name: "Subak Jatiluwih", farmerName: "Pak Wayan", plots: [plot])

    func testTheFarmColumnsAreNamedTheWayThePostgresTableIs() throws {
        let json = try encode(FarmRow(farm: farm))

        XCTAssertEqual(Set(json.keys), ["id", "name", "farmer_name"])
    }

    func testThePlotColumnsAreNamedTheWayThePostgresTableIs() throws {
        let boundary = PlotBoundary.wellKnownText(for: plot.corners) ?? ""

        let json = try encode(
            PlotRow(plot: plot, farmID: farm.id, number: 1, boundary: boundary))

        // No area_ha: the records generate it from the boundary and reject a value for it.
        XCTAssertEqual(Set(json.keys), ["id", "farm_id", "plot_number", "boundary"])
    }

    func testThePlotKeepsItsOwnIdSoPublishingTwiceDoesNotMakeASecondPlot() {
        let row = PlotRow(
            plot: plot, farmID: farm.id, number: 2,
            boundary: "SRID=4326;POLYGON((0 0, 1 0, 1 1, 0 0))")

        XCTAssertEqual(row.id, plot.id)
        XCTAssertEqual(row.farmID, farm.id)
        XCTAssertEqual(row.plotNumber, 2)
    }

    func testTheWriterIsLeftToTheRecords() throws {
        // Sending it would take a farm read back from somebody else off them on the next
        // publish. The column's own default names whoever is signed in.
        XCTAssertNil(try encode(FarmRow(farm: farm))["created_by"])
    }

    func testTheFarmsOwnNameIsSentNowTheFormAsksForOne() {
        let row = FarmRow(farm: farm)

        XCTAssertEqual(row.name, "Subak Jatiluwih")
        XCTAssertEqual(row.farmerName, "Pak Wayan")
    }

    func testThePlotsToKeepAreListedTheWayPostgrestParsesThem() {
        let first = UUID()
        let second = UUID()

        // Brackets, or the filter is not parsed at all.
        XCTAssertEqual(
            FarmUploader.list([first, second]),
            "(\(first.uuidString),\(second.uuidString))")
    }

    private func encode(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
