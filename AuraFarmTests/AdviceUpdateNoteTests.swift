//
//  AdviceUpdateNoteTests.swift
//  AuraFarmTests
//
//  Created by William Silvano Angga on 13/11/26.
//

import XCTest

@testable import AuraFarm

final class AdviceUpdateNoteTests: XCTestCase {
    func testOneChangedReadingIsNamed() {
        let old = SoilInputs(nitrogen: 100, ph: 6.5)
        let new = SoilInputs(nitrogen: 100, ph: 7.0)

        XCTAssertEqual(AdviceUpdateNote.text(from: old, to: new), "Updated with the new pH reading.")
    }

    func testAReadingThatWasAddedIsNamed() {
        let old = SoilInputs(nitrogen: 100)
        let new = SoilInputs(nitrogen: 100, ph: 6.5)

        XCTAssertEqual(AdviceUpdateNote.text(from: old, to: new), "Updated with the new pH reading.")
    }

    func testAReadingThatWasRemovedIsNamed() {
        let old = SoilInputs(nitrogen: 100, ph: 6.5)
        let new = SoilInputs(nitrogen: 100)

        XCTAssertEqual(
            AdviceUpdateNote.text(from: old, to: new), "Updated after the pH reading was removed.")
    }

    func testTheNamesReadAsTheyDoInThePrompt() {
        XCTAssertEqual(
            AdviceUpdateNote.text(from: SoilInputs(nitrogen: 90), to: SoilInputs(nitrogen: 100)),
            "Updated with the new nitrogen reading.")
        XCTAssertEqual(
            AdviceUpdateNote.text(
                from: SoilInputs(organicCarbonPercent: 2.5), to: SoilInputs(organicCarbonPercent: 3)),
            "Updated with the new organic carbon reading.")
    }

    func testSeveralChangesAreNotListed() {
        let old = SoilInputs(nitrogen: 100, ph: 6.5)
        let new = SoilInputs(nitrogen: 90, ph: 7.0)

        XCTAssertEqual(
            AdviceUpdateNote.text(from: old, to: new), "Updated with the new soil measurements.")
    }

    func testFirstMeasurementsAfterNone() {
        XCTAssertEqual(
            AdviceUpdateNote.text(from: nil, to: SoilInputs(ph: 6.5)),
            "Updated with the new soil measurements.")
    }

    func testAllMeasurementsRemoved() {
        XCTAssertEqual(
            AdviceUpdateNote.text(from: SoilInputs(ph: 6.5), to: nil),
            "Updated after the soil measurements were removed.")
    }
}
