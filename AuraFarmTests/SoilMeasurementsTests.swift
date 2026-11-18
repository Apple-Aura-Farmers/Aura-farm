//
//  SoilMeasurementsTests.swift
//  AuraFarmTests
//
//  Created by William Silvano Angga on 13/11/26.
//

import XCTest

@testable import AuraFarm

final class SoilMeasurementsTests: XCTestCase {
    func testNothingFilledInIsEmpty() {
        let soil = SoilMeasurements()
        XCTAssertTrue(soil.isEmpty)
        XCTAssertTrue(soil.rows.isEmpty)
        XCTAssertTrue(soil.problems.isEmpty)
    }

    func testAnyValueMakesItNotEmpty() {
        XCTAssertFalse(SoilMeasurements(ph: 6.5).isEmpty)
        XCTAssertFalse(SoilMeasurements(fertilizerProduct: "Urea").isEmpty)
        XCTAssertFalse(SoilMeasurements(fertilizerKilogramsPerHectare: 50).isEmpty)
    }

    func testPhOutsideZeroToFourteenIsAProblem() {
        XCTAssertEqual(SoilMeasurements(ph: 15).problems.count, 1)
        XCTAssertEqual(SoilMeasurements(ph: -1).problems.count, 1)
        XCTAssertTrue(SoilMeasurements(ph: 0).problems.isEmpty)
        XCTAssertTrue(SoilMeasurements(ph: 14).problems.isEmpty)
    }

    func testOrganicCarbonOverOneHundredPercentIsAProblem() {
        XCTAssertEqual(SoilMeasurements(organicCarbonPercent: 101).problems.count, 1)
        XCTAssertTrue(SoilMeasurements(organicCarbonPercent: 100).problems.isEmpty)
    }

    func testNegativeAmountsAreProblems() {
        let soil = SoilMeasurements(
            nitrogen: -1, phosphorus: -1, potassium: -1, fertilizerKilogramsPerHectare: -1)
        XCTAssertEqual(soil.problems.count, 4)
    }

    func testRowsComeInAFixedOrderAndLeaveOutEmptyValues() {
        let soil = SoilMeasurements(nitrogen: 100, potassium: 200, ph: 6.5)
        XCTAssertEqual(soil.rows.map(\.label), ["Nitrogen (N)", "Potassium (K)", "pH"])
    }

    func testRowsCarryTheirBandAndNote() {
        let soil = SoilMeasurements(nitrogen: 100, potassium: 200, ph: 7.9)
        XCTAssertEqual(soil.rows.map(\.band), [.standard, .high, .excessive])
        XCTAssertTrue(soil.rows.allSatisfy { $0.note != nil })
    }

    func testFertilizerRowHasNoBand() throws {
        let soil = SoilMeasurements(
            fertilizerProduct: "Urea", fertilizerKilogramsPerHectare: 50)
        let row = try XCTUnwrap(soil.rows.first)
        XCTAssertEqual(row.label, "Fertilizer")
        XCTAssertEqual(row.value, "Urea · 50 kg/ha")
        XCTAssertNil(row.band)
        XCTAssertNil(row.note)
    }

    func testFarmWithSoilSurvivesSavingAndLoading() throws {
        let soil = SoilMeasurements(nitrogen: 100, ph: 6.5, fertilizerProduct: "Compost")
        let farm = Farm(
            name: "Subak Jatiluwih", farmerName: "Pak Wayan",
            plots: [Plot(corners: [], soil: soil)])
        let data = try JSONEncoder().encode(farm)
        let loaded = try JSONDecoder().decode(Farm.self, from: data)
        XCTAssertEqual(loaded, farm)
    }

    /// Soil saved before a measurement had an id of its own, or an alert on it.
    func testSoilSavedBeforeIdsAndAlertsStillLoads() throws {
        let json = """
            {"nitrogen":100,"ph":6.5,"updatedAt":0}
            """
        let soil = try JSONDecoder().decode(SoilMeasurements.self, from: Data(json.utf8))

        XCTAssertEqual(soil.nitrogen, 100)
        XCTAssertNil(soil.scientistAlertedAt)
        // An id is made for it rather than the whole reading being lost.
        XCTAssertFalse(soil.isEmpty)
    }

    func testTheNutrientBarReadsWhatTheBandsMeanAndNotTheNumbers() {
        // In range on all three: as good as it gets.
        let good = SoilMeasurements(nitrogen: 100, phosphorus: 20, potassium: 130)
        XCTAssertEqual(good.npkHealth ?? 0, 0.9, accuracy: 0.0001)

        // Nothing filled in has nowhere to sit.
        XCTAssertNil(SoilMeasurements().npkHealth)

        // Far too little nitrogen reads worse than the same soil with it in range.
        let starved = SoilMeasurements(nitrogen: 1, phosphorus: 20, potassium: 130)
        XCTAssertLessThan(starved.npkHealth ?? 1, good.npkHealth ?? 0)
    }

    func testSoilWaitingOnAScientistIsNotNothingToKeep() {
        var soil = SoilMeasurements()
        XCTAssertTrue(soil.isEmpty)
        XCTAssertTrue(soil.isUnrecorded)

        soil.scientistAlertedAt = Date()
        // Still no numbers, but the asking is worth keeping.
        XCTAssertTrue(soil.isEmpty)
        XCTAssertFalse(soil.isUnrecorded)
    }

    /// Farms saved before soil measurements existed have no `soil` key.
    func testOlderFarmWithoutSoilStillLoads() throws {
        let json = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","farmerName":"Pak Wayan",\
            "corners":[],"createdAt":0}
            """
        let farm = try JSONDecoder().decode(Farm.self, from: Data(json.utf8))
        XCTAssertNil(farm.plots.first?.soil)
    }

    /// Soil used to belong to the farm; it now goes to the farm's first plot.
    func testFarmLevelSoilMovesToTheFirstPlot() throws {
        let json = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","farmerName":"Pak Wayan",\
            "corners":[{"latitude":0,"longitude":0}],"createdAt":0,\
            "soil":{"nitrogen":100,"updatedAt":0}}
            """
        let farm = try JSONDecoder().decode(Farm.self, from: Data(json.utf8))
        XCTAssertEqual(farm.plots.first?.soil?.nitrogen, 100)
    }
}
