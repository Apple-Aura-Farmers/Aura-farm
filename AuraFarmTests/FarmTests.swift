import XCTest

@testable import AuraFarm

final class FarmTests: XCTestCase {
    private let square = [
        GeoPoint(latitude: -8.4095, longitude: 115.1889),
        GeoPoint(latitude: -8.4095, longitude: 115.1900),
        GeoPoint(latitude: -8.4105, longitude: 115.1900),
        GeoPoint(latitude: -8.4105, longitude: 115.1889),
    ]

    func testTheFarmsAreaIsItsPlotsAddedUp() {
        let one = Plot(corners: square)
        let farm = Farm(name: "Subak", farmerName: "Pak Wayan", plots: [one, one])

        let single = one.areaSquareMetres ?? 0
        XCTAssertGreaterThan(single, 0)
        XCTAssertEqual(farm.areaSquareMetres ?? 0, single * 2, accuracy: 1)
    }

    func testAFarmWithNoLandMarkedHasNoArea() {
        let farm = Farm(name: "Subak", farmerName: "Pak Wayan", plots: [Plot(corners: [])])

        XCTAssertNil(farm.areaSquareMetres)
    }

    func testPlotsAreNumberedFromOneInTheOrderTheyAreHeld() {
        let first = Plot(corners: square)
        let second = Plot(corners: square)
        let farm = Farm(name: "Subak", farmerName: "Pak Wayan", plots: [first, second])

        XCTAssertEqual(farm.number(of: first), 1)
        XCTAssertEqual(farm.number(of: second), 2)
    }

    func testAFarmSavedBeforePlotsExistedKeepsItsOutlineAsItsFirstPlot() throws {
        let saved = """
            {
              "id": "6E1C2E3A-4D5F-4A6B-8C9D-0E1F2A3B4C5D",
              "farmerName": "Pak Wayan",
              "createdAt": "2026-11-01T02:00:00Z",
              "corners": [
                { "latitude": -8.4095, "longitude": 115.1889 },
                { "latitude": -8.4095, "longitude": 115.1900 },
                { "latitude": -8.4105, "longitude": 115.1900 }
              ]
            }
            """

        let farm = try decode(saved)

        XCTAssertEqual(farm.plots.count, 1)
        XCTAssertEqual(farm.plots.first?.corners.count, 3)
        // No name was asked for back then, so the farmer's stands in rather than showing blank.
        XCTAssertEqual(farm.name, "Pak Wayan")
    }

    func testAFarmSavedBeforePlotsExistedWithNoOutlineHasNoPlots() throws {
        let saved = """
            {
              "id": "6E1C2E3A-4D5F-4A6B-8C9D-0E1F2A3B4C5D",
              "farmerName": "Pak Wayan",
              "createdAt": "2026-11-01T02:00:00Z",
              "corners": []
            }
            """

        XCTAssertTrue(try decode(saved).plots.isEmpty)
    }

    func testEveryPlotIsANeighbourExceptTheOneBeingEdited() {
        let mine = Plot(corners: square)
        let theirs = Plot(corners: square)
        let farms = [
            Farm(name: "Subak", farmerName: "Pak Wayan", plots: [mine, theirs])
        ]

        XCTAssertEqual(farms.neighbours().map(\.id), [mine.id, theirs.id])
        XCTAssertEqual(farms.neighbours(excluding: mine.id).map(\.id), [theirs.id])
        // Labelled by the farm, which is what the editor draws over the land.
        XCTAssertEqual(farms.neighbours().first?.label, "Subak")
    }

    func testAPlotNameIsTakenWhateverTheCaseOrSpacing() {
        let farm = Farm(
            name: "Subak", farmerName: "Pak Wayan",
            plots: [Plot(name: "Tabanan", corners: square)])

        XCTAssertTrue(farm.hasPlot(named: "  tabanan "))
        XCTAssertFalse(farm.hasPlot(named: "Tabanan I"))
        // Nothing typed yet is not a clash.
        XCTAssertFalse(farm.hasPlot(named: "   "))
    }

    func testAPlotIsNamedByItsNumberOnScreen() {
        let first = Plot(name: "Tabanan", corners: square)
        let second = Plot(corners: square)
        let farm = Farm(name: "Subak", farmerName: "Pak Wayan", plots: [first, second])

        XCTAssertEqual(farm.title(of: first), "Plot 1")
        XCTAssertEqual(farm.title(of: second), "Plot 2")
    }

    func testAPlotNameSurvivesSavingAndLoading() throws {
        let farm = Farm(
            name: "Subak", farmerName: "Pak Wayan",
            plots: [Plot(name: "Tabanan", corners: square)])

        let data = try JSONEncoder().encode(farm)
        let loaded = try JSONDecoder().decode(Farm.self, from: data)

        XCTAssertEqual(loaded.plots.first?.name, "Tabanan")
    }

    private func decode(_ json: String) throws -> Farm {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Farm.self, from: Data(json.utf8))
    }
}
