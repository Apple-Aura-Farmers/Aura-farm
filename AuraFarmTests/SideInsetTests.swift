import CoreGraphics
import XCTest

@testable import AuraFarm

/// Phase 4a-fix 2 part C: the first and last columns sit the eyepiece circle's radius plus a
/// margin inside the left and right edges, so only sample is in view; the top and bottom edges
/// keep the old inset.
final class SideInsetTests: XCTestCase {
    private func run(
        width: Double, height: Double, radius: Double?, square: Bool = true, spacing: Double = 1.6
    ) -> (GuideSimulator, GuideSimulator.Result) {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: width, height: height)])
        let sim = GuideSimulator(drop: drop, start: CGPoint(x: 2.0, y: 2.0))
        sim.useFullCoverSlip {
            $0.columnSpacingFields = spacing
            $0.squareCoverSlip = square
            $0.eyepieceRadiusFields = radius
        }
        return (sim, sim.run())
    }

    private func column(_ number: Int, in result: GuideSimulator.Result) -> [FramePlacement] {
        result.placements.filter { $0.column == number }.sorted { $0.order < $1.order }
    }

    func testTheInsetIsTheRadiusPlusTheMarginAndNeverLessThanTheOldOne() {
        var thresholds = GuidedSweepThresholds()
        XCTAssertEqual(thresholds.sideInsetFields, 0.6, "no circle: as before")
        thresholds.eyepieceRadiusFields = 1.4
        XCTAssertEqual(thresholds.sideInsetFields, 1.55, accuracy: 1e-9)
        thresholds.eyepieceRadiusFields = 0.2
        XCTAssertEqual(thresholds.sideInsetFields, 0.6, accuracy: 1e-9, "never less")
        XCTAssertEqual(thresholds.columnInsetFields, 0.6, "the top and bottom keep this")
    }

    func testColumnOneStartsOneFiftyFiveFromTheLeftEdge() {
        let (_, wide) = run(width: 7, height: 7, radius: 1.4)
        let first = column(1, in: wide).map { Double($0.position.x) }.min() ?? .nan
        XCTAssertEqual(first, 1.55, accuracy: 0.3)
        let (_, plain) = run(width: 7, height: 7, radius: nil)
        let old = column(1, in: plain).map { Double($0.position.x) }.min() ?? .nan
        XCTAssertEqual(old, 0.6, accuracy: 0.3, "no circle: as before")
    }

    func testTheLastColumnSitsTheInsetInsideAFoundRightEdge() {
        // Not square: the right edge is found by the step, not predicted.
        // Columns at 1.55 and 3.95; the next step (6.35) is past the edge at 6.0.
        let (sim, result) = run(width: 6, height: 3, radius: 1.4, square: false, spacing: 2.4)
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertNotEqual(sim.guide.rightEdgeSource, "predicted")
        let lastNumber = result.placements.map(\.column).max() ?? 0
        XCTAssertEqual(lastNumber, 3, "an extra last column at the edge less the inset")
        let last = column(lastNumber, in: result).map { Double($0.position.x) }.max() ?? .nan
        XCTAssertEqual(last, 6 - 1.55, accuracy: 0.4)
    }

    func testTheLastColumnSitsTheInsetInsideAPredictedRightEdge() {
        let (sim, result) = run(width: 7.5, height: 7.5, radius: 1.4)
        XCTAssertEqual(result.finishReason, .rightEdge)
        XCTAssertEqual(sim.guide.rightEdgeSource, "predicted")
        let lastNumber = result.placements.map(\.column).max() ?? 0
        let last = column(lastNumber, in: result).map { Double($0.position.x) }.max() ?? .nan
        XCTAssertEqual(last, 7.5 - 1.55, accuracy: 0.4)
    }

    func testTheInwardStartAfterABottomEdgeIsStillSixTenths() {
        let (_, result) = run(width: 7, height: 2.4, radius: 1.4)
        let two = column(2, in: result)
        XCTAssertEqual(Double(two.first?.position.y ?? 0), 2.4 - 0.6, accuracy: 0.3, "\(two)")
    }

    func testTheLeftEdgeThePredictionDrawsIsTheInsetOutFromColumnOne() {
        let (sim, _) = run(width: 7, height: 7, radius: 1.4)
        XCTAssertEqual(sim.guide.predictedEdges.leftX ?? .nan, 0, accuracy: 0.4)
    }

    func testTheRunRecordKeepsTheInsetAndOldRecordsHaveNone() throws {
        var record = GuideRunRecord.previewForTests
        record.sideInsetFields = 1.55
        let data = try GuideRunRecord.encoder().encode(record)
        XCTAssertEqual(
            try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data).sideInsetFields, 1.55)
        record.sideInsetFields = nil
        let plain = try GuideRunRecord.encoder().encode(record)
        XCTAssertNil(
            try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: plain).sideInsetFields)
    }

    // MARK: The distance text at the arrow's tail

    func testTheDistanceLabelSitsBesideTheTailOnTheLineOfTheArrow() {
        let size = CGSize(width: 390, height: 420)
        // An arrow pointing down, pinned near the bottom: the tail is above it.
        let down = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 195, y: 340), angle: .pi / 2, viewSize: size)
        XCTAssertLessThan(down.y, 340 - 22, "behind the tail, not at the tip")
        XCTAssertEqual(Double(down.x), 195, accuracy: 1e-6)
        // Pointing right: the text is to the left of the tail.
        let right = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 320, y: 210), angle: 0, viewSize: size)
        XCTAssertLessThan(right.x, 320 - 22)
        XCTAssertEqual(Double(right.y), 210, accuracy: 1e-6)
        // Pointing left and up: behind the tail is right, and below.
        let left = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 70, y: 210), angle: .pi, viewSize: size)
        XCTAssertGreaterThan(left.x, 70 + 22)
        let up = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 195, y: 80), angle: -.pi / 2, viewSize: size)
        XCTAssertGreaterThan(up.y, 80 + 22)
    }

    func testTheDistanceLabelIsNudgedInsideThePicture() {
        let size = CGSize(width: 390, height: 420)
        // Pinned in the corner pointing at the edge: the tail is near the picture's edge.
        let corner = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 8, y: 8), angle: -.pi * 3 / 4, viewSize: size)
        XCTAssertGreaterThanOrEqual(Double(corner.x), 42)
        XCTAssertGreaterThanOrEqual(Double(corner.y), 10)
        let far = GuideOverlayModel.distanceLabelCentre(
            arrowCentre: CGPoint(x: 385, y: 415), angle: .pi / 4, viewSize: size)
        XCTAssertLessThanOrEqual(Double(far.x), 390 - 42)
        XCTAssertLessThanOrEqual(Double(far.y), 420 - 10)
    }
}
