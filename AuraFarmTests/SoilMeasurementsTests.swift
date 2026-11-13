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
        var farm = Farm(farmerName: "Pak Wayan", corners: [])
        farm.soil = SoilMeasurements(nitrogen: 100, ph: 6.5, fertilizerProduct: "Compost")
        let data = try JSONEncoder().encode(farm)
        let loaded = try JSONDecoder().decode(Farm.self, from: data)
        XCTAssertEqual(loaded, farm)
    }

    /// Farms saved before soil measurements existed have no `soil` key.
    func testOlderFarmWithoutSoilStillLoads() throws {
        let json = """
            {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","farmerName":"Pak Wayan",\
            "corners":[],"createdAt":0}
            """
        let farm = try JSONDecoder().decode(Farm.self, from: Data(json.utf8))
        XCTAssertNil(farm.soil)
    }
}
