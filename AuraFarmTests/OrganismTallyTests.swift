import CoreGraphics
import XCTest

@testable import AuraFarm

final class OrganismTallyTests: XCTestCase {
    private func found(
        _ label: String, x: Double, y: Double, side: Double = 40
    ) -> OrganismTally.Found {
        OrganismTally.Found(
            label: label,
            box: CGRect(x: x, y: y, width: side, height: side),
            confidence: 0.9
        )
    }

    func testOneOrganismSeenAgainKeepsItsIDAndIsCountedOnce() {
        var tally = OrganismTally()
        tally.update(found: [found("Nematoda", x: 100, y: 100)], pictureMoved: .zero)
        // The slide moved 60 px to the right, so the same organism lands 60 px further on.
        tally.update(found: [found("Nematoda", x: 160, y: 100)], pictureMoved: CGPoint(x: 60, y: 0))
        tally.update(found: [found("Nematoda", x: 220, y: 100)], pictureMoved: CGPoint(x: 60, y: 0))

        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.tracks.map(\.id), [1])
    }

    func testSomethingElseInTheFrameGetsItsOwnID() {
        var tally = OrganismTally()
        tally.update(found: [found("Nematoda", x: 100, y: 100)], pictureMoved: .zero)
        tally.update(
            found: [found("Nematoda", x: 100, y: 100), found("Nematoda", x: 400, y: 300)],
            pictureMoved: .zero
        )

        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(tally.tracks.map(\.id).sorted(), [1, 2])
        XCTAssertEqual(tally.countByLabel["Nematoda"], 2)
    }

    func testTwoSpeciesInTheSamePlaceAreNotTheSameThing() {
        var tally = OrganismTally()
        tally.update(found: [found("Nematoda", x: 100, y: 100)], pictureMoved: .zero)
        tally.update(found: [found("Arcellinida", x: 100, y: 100)], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(tally.countByLabel["Nematoda"], 1)
        XCTAssertEqual(tally.countByLabel["Arcellinida"], 1)
    }

    func testAMissedFrameOrTwoDoesNotCountTheSameOrganismTwice() {
        var tally = OrganismTally()
        tally.update(found: [found("Digononta", x: 100, y: 100)], pictureMoved: .zero)
        tally.update(found: [], pictureMoved: .zero)
        tally.update(found: [], pictureMoved: .zero)
        tally.update(found: [found("Digononta", x: 100, y: 100)], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 1)
    }

    func testATrackIsDroppedOnceItHasBeenGoneTooLong() {
        var tally = OrganismTally()
        tally.patience = 2
        tally.update(found: [found("Monogononta", x: 100, y: 100)], pictureMoved: .zero)
        for _ in 0..<3 { tally.update(found: [], pictureMoved: .zero) }

        XCTAssertTrue(tally.tracks.isEmpty)
        // Known limit: ground covered twice is counted twice. The sweep walks rows that
        // barely overlap, so this costs little, but it is why the count is a floor.
        tally.update(found: [found("Monogononta", x: 100, y: 100)], pictureMoved: .zero)
        XCTAssertEqual(tally.total, 2)
    }

    func testAnOrganismThatStaysPutWhileTheSlideMovesIsNotCountedAgain() {
        var tally = OrganismTally()
        tally.update(found: [found("Hypotrichida", x: 300, y: 200)], pictureMoved: .zero)
        // Walking a row: the picture moves left as the slide is pushed right.
        for step in 1...4 {
            tally.update(
                found: [found("Hypotrichida", x: 300 - Double(step) * 50, y: 200)],
                pictureMoved: CGPoint(x: -50, y: 0)
            )
        }

        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.tracks.first?.box.minX, 100)
    }

    func testJitterBetweenFramesIsTheSameOrganism() {
        var tally = OrganismTally()
        tally.update(found: [found("Nematoda", x: 100, y: 100)], pictureMoved: .zero)
        // Half a box away is inside the match distance; the box also breathes a little.
        tally.update(
            found: [found("Nematoda", x: 112, y: 108, side: 44)], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 1)
    }

    func testResetForgetsEverything() {
        var tally = OrganismTally()
        tally.update(found: [found("Nematoda", x: 100, y: 100)], pictureMoved: .zero)
        tally.reset()

        XCTAssertEqual(tally.total, 0)
        XCTAssertTrue(tally.tracks.isEmpty)
        XCTAssertTrue(tally.countByLabel.isEmpty)
    }
}
