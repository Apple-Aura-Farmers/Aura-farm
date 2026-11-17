import SwiftUI
import XCTest

@testable import AuraFarm

/// The colour a farmer's land is drawn in.
final class FarmerColourTests: XCTestCase {
    func testAFarmerKeepsTheSameColourBetweenLaunches() {
        // Worked out from the name, not from Swift's own hashing, which is seeded afresh
        // every launch and would repaint the map each time the app opened.
        XCTAssertEqual(
            FarmerColour.index(for: "Pak Wayan"), FarmerColour.index(for: "Pak Wayan"))
        XCTAssertEqual(FarmerColour.index(for: "Pak Wayan"), 1)
    }

    func testSpacingAndCapitalsAreTheSameFarmer() {
        XCTAssertEqual(
            FarmerColour.index(for: "  pak wayan "), FarmerColour.index(for: "Pak Wayan"))
    }

    func testEveryFarmerOnThePhoneGetsADifferentColour() {
        // Two of these four want the same colour, so one has to move along.
        let names = ["Pak Wayan", "Ibu Made", "Pak Agung", "Pak Dayat"]

        let colours = FarmerColour.colours(for: names)

        XCTAssertEqual(colours.count, names.count)
        XCTAssertEqual(Set(colours.values).count, names.count)
    }

    func testAddingAFarmerDoesNotRepaintTheOthers() {
        let before = FarmerColour.colours(for: ["Ibu Made", "Pak Wayan"])
        let after = FarmerColour.colours(for: ["Ibu Made", "Pak Wayan", "Pak Zayan"])

        XCTAssertEqual(before["ibu made"], after["ibu made"])
        XCTAssertEqual(before["pak wayan"], after["pak wayan"])
    }

    func testPastTheEndOfThePaletteTheColoursStartAgain() {
        let many = (0..<20).map { "Farmer \($0)" }

        let colours = FarmerColour.colours(for: many)

        XCTAssertEqual(colours.count, many.count)
        XCTAssertEqual(Set(colours.values).count, FarmerColour.palette.count)
    }

    func testEveryNameLandsOnAColourThatExists() {
        for name in ["", "x", "Pak Wayan", String(repeating: "a", count: 500)] {
            let index = FarmerColour.index(for: name)
            XCTAssertTrue(FarmerColour.palette.indices.contains(index), name)
        }
    }
}
