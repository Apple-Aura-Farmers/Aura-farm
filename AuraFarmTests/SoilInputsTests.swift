//
//  SoilInputsTests.swift
//  AuraFarmTests
//
//  Created by William Silvano Angga on 13/11/26.
//

import XCTest

@testable import AuraFarm

final class SoilInputsTests: XCTestCase {
    func testNoMeasurementsIsNothing() {
        XCTAssertNil(SoilInputs(nil))
        XCTAssertNil(SoilInputs(SoilMeasurements()))
    }

    func testAFertilizerNoteAloneIsNothingTheAdviceCanRead() {
        let soil = SoilMeasurements(fertilizerProduct: "Urea", fertilizerKilogramsPerHectare: 50)

        XCTAssertNil(SoilInputs(soil))
    }

    func testWhenTheMeasurementsWereSavedDoesNotMatter() {
        let earlier = SoilMeasurements(ph: 6.5, updatedAt: Date(timeIntervalSince1970: 0))
        let later = SoilMeasurements(ph: 6.5, updatedAt: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(SoilInputs(earlier), SoilInputs(later))
    }

    func testFertilizerDoesNotChangeIt() {
        let plain = SoilMeasurements(ph: 6.5)
        let withFertilizer = SoilMeasurements(
            ph: 6.5, fertilizerProduct: "Urea", fertilizerKilogramsPerHectare: 50)

        XCTAssertEqual(SoilInputs(plain), SoilInputs(withFertilizer))
    }

    func testAChangedNumberIsADifference() {
        XCTAssertNotEqual(SoilInputs(SoilMeasurements(ph: 6.5)), SoilInputs(SoilMeasurements(ph: 6.6)))
        XCTAssertNotEqual(
            SoilInputs(SoilMeasurements(ph: 6.5)),
            SoilInputs(SoilMeasurements(nitrogen: 100, ph: 6.5)))
    }

    func testReadingsComeInAFixedOrderWithTheirUnitsAndBands() throws {
        let inputs = try XCTUnwrap(
            SoilInputs(
                SoilMeasurements(nitrogen: 100, potassium: 200, ph: 6.5, organicCarbonPercent: 2.5)))

        XCTAssertEqual(inputs.readings.map(\.name), ["nitrogen", "potassium", "pH", "organic carbon"])
        XCTAssertEqual(inputs.readings.map(\.short), ["N", "K", "pH", "organic carbon"])
        XCTAssertEqual(inputs.readings.map(\.unit), ["mg/kg", "mg/kg", "", "%"])
        XCTAssertEqual(inputs.readings.map(\.band), [.standard, .high, .standard, .standard])
        XCTAssertEqual(inputs.readings.map(\.value), [100, 200, 6.5, 2.5])
    }

    func testBandEdgesFollowTheStandard() {
        func band(_ nitrogen: Double) -> SoilBand? {
            SoilInputs(nitrogen: nitrogen).readings.first?.band
        }

        XCTAssertEqual(band(79.9), .low)
        XCTAssertEqual(band(80), .standard)
        XCTAssertEqual(band(120), .standard)
        XCTAssertEqual(band(120.1), .high)
        XCTAssertEqual(band(150), .high)
        XCTAssertEqual(band(150.1), .excessive)
    }

    func testItSurvivesARoundTrip() throws {
        let inputs = SoilInputs(nitrogen: 100, phosphorus: nil, potassium: 150, ph: 6.5)

        let decoded = try JSONDecoder().decode(SoilInputs.self, from: JSONEncoder().encode(inputs))

        XCTAssertEqual(decoded, inputs)
    }
}
