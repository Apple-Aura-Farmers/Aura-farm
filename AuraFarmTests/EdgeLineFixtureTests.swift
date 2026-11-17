import ImageIO
import XCTest

@testable import AuraFarm

/// Phase 2p part D: the detector on real frames. The fixtures are 400 px crops centred on the
/// eyepiece circle (705, 455) of snapshots from the 16 Nov 2026 15:32 run (full-cover mode,
/// soil): edge-a, edge-b and edge-c are frames 017.10, 020.26 and 024.50 (the cover-slip edge,
/// a clear dark line, nearly horizontal in the frame, with sample on one side and almost empty
/// glass on the other, the frame's bottom); edge-weak is frame 005.77 (a dense and sparse
/// boundary); ghost-b is a frame with no edge.
final class EdgeLineFixtureTests: XCTestCase {
    private let box = CGRect(x: 39, y: 39, width: 322, height: 322)
    /// Heading toward the empty side (frame +y), and a leg direction (frame +x).
    private let towardEmpty = CGPoint(x: 0, y: 1)
    private let along = CGPoint(x: 1, y: 0)

    private func detect(_ name: String, normal: CGPoint) throws -> EdgeLine {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: name, withExtension: "png"), "missing \(name)")
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let luma = try XCTUnwrap(RegistrationFilter.luma(of: image))
        let buffer = SyntheticFrame.make(width: luma.width, height: luma.height) { x, y in
            luma.bytes[y * luma.width + x]
        }
        let grid = try XCTUnwrap(EdgeLineGrid.sample(of: buffer, in: box, step: 2))
        return try XCTUnwrap(EdgeLineDetector.detect(grid: grid, box: box, normal: normal))
    }

    private func describe(_ name: String, _ normal: String, _ line: EdgeLine) -> String {
        String(
            format: "FIXTURE %@ normal %@: strength %.1f coverage %.2f run %d angle %.1f offset %.3f "
                + "residual - before %.1f beyond %.1f candidate %d",
            name, normal, line.strength, line.coverage, line.longestRun, line.angleDegrees,
            line.offsetFields, line.beforeEnergy ?? -1, line.beyondEnergy ?? -1,
            twoFactor(line) ? 1 : 0)
    }

    /// The line rule's candidate: the detector's (strength and coverage or run) AND little
    /// texture beyond the line (`LineEdgeThresholds.beyondShareMax`).
    private func twoFactor(_ line: EdgeLine) -> Bool {
        guard line.isCandidate, let before = line.beforeEnergy, let beyond = line.beyondEnergy
        else { return false }
        return beyond <= LineEdgeThresholds().beyondShareMax * before
    }

    func testTheCoverSlipEdgeIsACandidateTowardTheEmptySideWithLittleBeyondIt() throws {
        for name in ["edge-a", "edge-b", "edge-c"] {
            let line = try detect(name, normal: towardEmpty)
            print(describe(name, "+y", line))
            XCTAssertTrue(line.isCandidate, name)
            XCTAssertGreaterThanOrEqual(line.strength, 20, name)
            XCTAssertLessThanOrEqual(abs(line.angleDegrees), 15, name)
            let before = try XCTUnwrap(line.beforeEnergy)
            let beyond = try XCTUnwrap(line.beyondEnergy)
            XCTAssertLessThanOrEqual(
                beyond, LineEdgeThresholds().beyondShareMax * before, name)
        }
    }

    func testTheSameFramesAlongALegDirectionAreNotCandidates() throws {
        for name in ["edge-a", "edge-b", "edge-c"] {
            let line = try detect(name, normal: along)
            print(describe(name, "+x", line))
            XCTAssertFalse(line.isCandidate, name)
        }
    }

    func testAFrameWithNoEdgeIsNotACandidateEitherWay() throws {
        for normal in [towardEmpty, along] {
            let line = try detect("ghost-b", normal: normal)
            print(describe("ghost-b", normal == towardEmpty ? "+y" : "+x", line))
            XCTAssertFalse(twoFactor(line))
        }
    }

    func testTheWeakDenseSparseBoundaryIsReportedNotAsserted() throws {
        // Frame 005.77, a dense and sparse boundary. Measured (322 px box, step 2): normal +y
        // strength 9.4, coverage 1.00, angle 18.0, offset -0.301, before 74.1, beyond 18.2, not a
        // candidate; normal +x strength 6.3, coverage 0.38, angle 31.5, not a candidate.
        for normal in [towardEmpty, along] {
            let line = try detect("edge-weak", normal: normal)
            print(describe("edge-weak", normal == towardEmpty ? "+y" : "+x", line))
        }
    }

    // MARK: Phase 2q part E: the dark-lighting frames the helper marked by hand (16 Nov 22:04)

    /// Prints every fixture on both normals so the next phase can set thresholds from them.
    func testTableOfEveryFixtureOnBothNormals() throws {
        let table: [(String, [(String, CGPoint)])] = [
            ("edge-a", [("+y", towardEmpty), ("+x", along)]),
            ("edge-b", [("+y", towardEmpty), ("+x", along)]),
            ("edge-c", [("+y", towardEmpty), ("+x", along)]),
            ("edge-weak", [("+y", towardEmpty), ("+x", along)]),
            ("ghost-b", [("+y", towardEmpty), ("+x", along)]),
            ("edge-dark-051-46", [("+y", CGPoint(x: 0, y: 1)), ("-y", CGPoint(x: 0, y: -1))]),
            ("edge-dark-194-61", [("+x", CGPoint(x: 1, y: 0)), ("-x", CGPoint(x: -1, y: 0))]),
        ]
        for (name, normals) in table {
            for (label, normal) in normals {
                print(describe(name, label, try detect(name, normal: normal)))
            }
        }
    }

    /// Frame 194.61 (top-left corner): sample on the right, less detail on the left (-x), which
    /// reads stronger (7.2 against 6.2). Frame 051.46 (left edge, sample above, less detail below)
    /// does NOT: +y 2.9 against -y 3.1, reported in the table and not asserted. The dark
    /// thresholds are for the next phase.
    func testTheNormalTowardTheLessDetailSideReadsStrongerOnTheCornerFrame() throws {
        let toward = try detect("edge-dark-194-61", normal: CGPoint(x: -1, y: 0))
        let away = try detect("edge-dark-194-61", normal: CGPoint(x: 1, y: 0))
        XCTAssertGreaterThan(toward.strength, away.strength)
    }
}
