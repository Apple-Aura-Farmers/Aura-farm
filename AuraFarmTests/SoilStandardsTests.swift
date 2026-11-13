//
//  SoilStandardsTests.swift
//  AuraFarmTests
//
//  Created by William Silvano Angga on 13/11/26.
//

import XCTest

@testable import AuraFarm

final class SoilStandardsTests: XCTestCase {
    func testNitrogenBoundaries() {
        let nitrogen = SoilStandards.nitrogen
        XCTAssertEqual(nitrogen.band(for: 79.9), .low)
        XCTAssertEqual(nitrogen.band(for: 80), .standard)
        XCTAssertEqual(nitrogen.band(for: 120), .standard)
        XCTAssertEqual(nitrogen.band(for: 120.1), .high)
        XCTAssertEqual(nitrogen.band(for: 150), .high)
        XCTAssertEqual(nitrogen.band(for: 150.1), .excessive)
    }

    func testPhBoundaries() {
        let ph = SoilStandards.ph
        XCTAssertEqual(ph.band(for: 5.9), .low)
        XCTAssertEqual(ph.band(for: 6.0), .standard)
        XCTAssertEqual(ph.band(for: 7.2), .standard)
        XCTAssertEqual(ph.band(for: 7.21), .high)
        XCTAssertEqual(ph.band(for: 7.8), .high)
        XCTAssertEqual(ph.band(for: 7.81), .excessive)
    }

    func testOrganicCarbonBoundaries() {
        let carbon = SoilStandards.organicCarbon
        XCTAssertEqual(carbon.band(for: 1.9), .low)
        XCTAssertEqual(carbon.band(for: 2.0), .standard)
        XCTAssertEqual(carbon.band(for: 3.5), .standard)
        XCTAssertEqual(carbon.band(for: 6.0), .high)
        XCTAssertEqual(carbon.band(for: 6.1), .excessive)
    }

    func testEveryStandardHasANoteForEveryBand() {
        let standards: [(String, SoilStandard)] = [
            ("nitrogen", SoilStandards.nitrogen),
            ("phosphorus", SoilStandards.phosphorus),
            ("potassium", SoilStandards.potassium),
            ("pH", SoilStandards.ph),
            ("organic carbon", SoilStandards.organicCarbon),
        ]
        let bands: [SoilBand] = [.low, .standard, .high, .excessive]
        for (name, standard) in standards {
            for band in bands {
                XCTAssertNotNil(standard.note(for: band), "\(name) has no note for \(band.label)")
            }
        }
    }

    func testEveryNoteHasAnAction() {
        let standards = [
            SoilStandards.nitrogen, SoilStandards.phosphorus, SoilStandards.potassium,
            SoilStandards.ph, SoilStandards.organicCarbon,
        ]
        for standard in standards {
            for band in [SoilBand.low, .standard, .high, .excessive] {
                let action = standard.note(for: band)?.action ?? ""
                XCTAssertFalse(action.isEmpty)
            }
        }
    }

    /// A high reading is good news for potassium and not for pH, so the tone follows the
    /// meaning and not the band's name.
    func testToneFollowsMeaningNotBandName() {
        XCTAssertEqual(SoilStandards.potassium.note(for: .high)?.tone, .good)
        XCTAssertEqual(SoilStandards.ph.note(for: .high)?.tone, .watch)
        XCTAssertEqual(SoilStandards.nitrogen.note(for: .excessive)?.tone, .act)
        XCTAssertEqual(SoilStandards.nitrogen.note(for: .standard)?.tone, .good)
    }

    func testStandardRangeDescription() {
        XCTAssertEqual(SoilStandards.nitrogen.description, "80–120")
        XCTAssertEqual(SoilStandards.potassium.description, "120–180")
    }
}
