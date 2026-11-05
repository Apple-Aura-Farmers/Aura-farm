import CoreGraphics
import XCTest

@testable import MicroscopeCounter

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
        tally.update(found: [found("paramecium", x: 100, y: 100)], pictureMoved: .zero)
        // The picture moved 60 px to the right, so the same organism lands 60 px further on.
        tally.update(found: [found("paramecium", x: 160, y: 100)], pictureMoved: CGPoint(x: 60, y: 0))
        tally.update(found: [found("paramecium", x: 220, y: 100)], pictureMoved: CGPoint(x: 60, y: 0))

        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.tracks.map(\.id), [1])
    }

    func testSomethingSeenInOnlyOneFrameIsNotCounted() {
        var tally = OrganismTally()
        // The model puts a box up for one frame and never again. That is flicker, not an
        // organism, and it is what swamped the count before.
        tally.update(found: [found("euglena", x: 100, y: 100)], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 0)
        XCTAssertTrue(tally.visible.isEmpty)
    }

    func testSomethingElseInTheFrameGetsItsOwnID() {
        var tally = OrganismTally()
        let one = found("paramecium", x: 100, y: 100)
        let other = found("paramecium", x: 400, y: 300)
        tally.update(found: [one], pictureMoved: .zero)
        tally.update(found: [one, other], pictureMoved: .zero)
        tally.update(found: [one, other], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(tally.tracks.map(\.id).sorted(), [1, 2])
        XCTAssertEqual(tally.countByLabel["paramecium"], 2)
    }

    func testTwoSpeciesInTheSamePlaceAreNotTheSameThing() {
        var tally = OrganismTally()
        let ciliate = found("paramecium", x: 100, y: 100)
        let flagellate = found("euglena", x: 100, y: 100)
        tally.update(found: [ciliate, flagellate], pictureMoved: .zero)
        tally.update(found: [ciliate, flagellate], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 2)
        XCTAssertEqual(tally.countByLabel["paramecium"], 1)
        XCTAssertEqual(tally.countByLabel["euglena"], 1)
    }

    func testAMissedFrameOrTwoDoesNotCountTheSameOrganismTwice() {
        var tally = OrganismTally()
        let drifter = found("stentor", x: 100, y: 100)
        tally.update(found: [drifter], pictureMoved: .zero)
        tally.update(found: [drifter], pictureMoved: .zero)
        tally.update(found: [], pictureMoved: .zero)
        tally.update(found: [], pictureMoved: .zero)
        tally.update(found: [drifter], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 1)
    }

    func testATrackIsDroppedOnceItHasBeenGoneTooLong() {
        var tally = OrganismTally()
        tally.patience = 2
        let drifter = found("vorticella", x: 100, y: 100)
        tally.update(found: [drifter], pictureMoved: .zero)
        tally.update(found: [drifter], pictureMoved: .zero)
        for _ in 0..<3 { tally.update(found: [], pictureMoved: .zero) }

        XCTAssertTrue(tally.tracks.isEmpty)
        XCTAssertEqual(tally.total, 1)

        // Known limit: ground covered twice is counted twice. The rows of a sweep barely
        // overlap, so this costs little, but it is why the count is a floor.
        tally.update(found: [drifter], pictureMoved: .zero)
        tally.update(found: [drifter], pictureMoved: .zero)
        XCTAssertEqual(tally.total, 2)
    }

    func testAnOrganismThatStaysPutWhileTheSlideMovesIsNotCountedAgain() {
        var tally = OrganismTally()
        tally.update(found: [found("volvox", x: 300, y: 200)], pictureMoved: .zero)
        // Walking a row: the picture moves left as the slide is pushed right.
        for step in 1...4 {
            tally.update(
                found: [found("volvox", x: 300 - Double(step) * 50, y: 200)],
                pictureMoved: CGPoint(x: -50, y: 0)
            )
        }

        XCTAssertEqual(tally.total, 1)
        XCTAssertEqual(tally.tracks.first?.box.minX, 100)
    }

    func testJitterBetweenFramesIsTheSameOrganism() {
        var tally = OrganismTally()
        tally.update(found: [found("paramecium", x: 100, y: 100)], pictureMoved: .zero)
        // Within a body width is the same organism; the box also breathes a little.
        tally.update(found: [found("paramecium", x: 112, y: 108, side: 44)], pictureMoved: .zero)

        XCTAssertEqual(tally.total, 1)
    }

    func testTheCountedTracksAreReturnedWhenTheyAreCounted() {
        var tally = OrganismTally()
        let ciliate = found("paramecium", x: 100, y: 100)
        XCTAssertTrue(tally.update(found: [ciliate], pictureMoved: .zero).isEmpty)
        XCTAssertEqual(tally.update(found: [ciliate], pictureMoved: .zero).map(\.id), [1])
        XCTAssertTrue(tally.update(found: [ciliate], pictureMoved: .zero).isEmpty)
    }

    func testResetForgetsEverything() {
        var tally = OrganismTally()
        let ciliate = found("paramecium", x: 100, y: 100)
        tally.update(found: [ciliate], pictureMoved: .zero)
        tally.update(found: [ciliate], pictureMoved: .zero)
        tally.reset()

        XCTAssertEqual(tally.total, 0)
        XCTAssertTrue(tally.tracks.isEmpty)
        XCTAssertTrue(tally.countByLabel.isEmpty)
    }

    func testTheRegistrationShiftIsTurnedRoundForTheTally() {
        // The registration reports the move that puts this frame back on the one before, so
        // a thing that stayed put went the other way.
        XCTAssertEqual(
            CameraQualityModel.pictureMoved(registered: CGPoint(x: 12, y: -4)),
            CGPoint(x: -12, y: 4)
        )
        XCTAssertEqual(CameraQualityModel.pictureMoved(registered: nil), .zero)
    }
}
