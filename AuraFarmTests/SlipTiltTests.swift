import CoreGraphics
import XCTest

@testable import AuraFarm

/// Step 3: columns that follow the cover slip's tilt, the tilted early limit from column 1's top or
/// bottom edge, and the stage's tilt reaching the guide's axes before Start scan.
///
/// Sign convention (proved against the detector below): an edge line's `angleDegrees` turns the
/// heading's normal by `R(a) = [[cos a, -sin a], [sin a, cos a]]` in x-right, y-down axes. For the
/// left edge (heading (-1, 0)) a positive angle makes the edge run toward screen-left as it goes
/// down: dx/dy = -tan(a). For a top or bottom edge (heading (0, -1) or (0, 1)) it makes dy/dx =
/// +tan(a). The columns' slope is dx/dy = -tan(left edge angle), so their distance to the edge is
/// constant.
final class SlipTiltTests: XCTestCase {
    // MARK: The sign, against the real detector

    private func luma(_ edge: (Double, Double) -> Double) -> EdgeLineGrid {
        let cells = 200
        var state: UInt64 = 12345
        var values = [Float](repeating: 100, count: cells * cells)
        for y in 0..<cells {
            for x in 0..<cells {
                let dx = Double(x) + 0.5 - Double(cells) / 2
                let dy = Double(y) + 0.5 - Double(cells) / 2
                var value: Float = 100
                if edge(dx, dy) > 0 { value += 100 }
                state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                if Double(state >> 33) / Double(1 << 31) < 0.03 { value -= 40 }
                values[y * cells + x] = value
            }
        }
        return EdgeLineGrid(luma: values, width: cells, height: cells, step: 2)
    }

    private let box = CGRect(x: 100, y: 100, width: 400, height: 400)

    /// A physical left edge leaning so that x falls as y grows (dx/dy = -tan 7 degrees); the
    /// content beyond it (to the left) is the brighter side.
    func testALeftEdgeThatRunsLeftGoingDownReadsAPositiveAngleAndSoDoesTheSlope() throws {
        let a = 7 * Double.pi / 180
        // Signed distance to the line along the leftward normal (-cos a, -sin a).
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: luma { dx, dy in -dx * cos(a) - dy * sin(a) - 10 }, box: box,
                normal: CGPoint(x: -1, y: 0)))
        // The detector searches in steps of a few degrees: the sign and the size are what matter.
        XCTAssertGreaterThan(line.angleDegrees, 0)
        XCTAssertEqual(line.angleDegrees, 7, accuracy: 3.5)
        // The direction of that line, the way the route reads the angle: dx/dy = -tan(angle).
        XCTAssertEqual(-tan(line.angleDegrees * .pi / 180), -tan(a), accuracy: 0.06)
    }

    func testATopEdgeThatRunsDownGoingRightReadsAPositiveAngleAndSoDoesTheSlope() throws {
        let a = 7 * Double.pi / 180
        // The line y = c + tan(a) x; ahead (up) is brighter: along the normal (sin a, -cos a).
        let line = try XCTUnwrap(
            EdgeLineDetector.detect(
                grid: luma { dx, dy in dx * sin(a) - dy * cos(a) - 10 }, box: box,
                normal: CGPoint(x: 0, y: -1)))
        // The detector searches in steps of a few degrees: the sign and the size are what matter.
        XCTAssertGreaterThan(line.angleDegrees, 0)
        XCTAssertEqual(line.angleDegrees, 7, accuracy: 3.5)
        XCTAssertEqual(tan(line.angleDegrees * .pi / 180), tan(a), accuracy: 0.06)
    }

    // MARK: Scripting a route

    private func edgeLine(angle: Double, offset: Double) -> EdgeLine {
        EdgeLine(
            strength: 30, coverage: 1, longestRun: 8, angleDegrees: angle, offsetFields: offset,
            sign: 1, slideResidualFields: offset > 0.15 ? 0.05 : nil, path: [], isCandidate: true,
            beforeEnergy: nil, beyondEnergy: nil)
    }

    /// Moves toward the current target 0.1 field a reading and holds still on it, `line` giving the
    /// edge line seen from where the view will be; stops when `stop` says so.
    @discardableResult
    private func drive(
        _ route: ScriptedRoute, readings: Int, line: ((CGPoint) -> EdgeLine?)? = nil,
        until stop: ((GuideStep) -> Bool)? = nil
    ) -> Bool {
        for _ in 0..<readings {
            guard let target = route.last.target else { return false }
            let dx = Double(target.x - route.position.x)
            let dy = Double(target.y - route.position.y)
            let length = hypot(dx, dy)
            let moving = length > 0.05
            let size = moving ? min(0.1, length) : 0
            let move = moving ? CGPoint(x: dx / length * size, y: dy / length * size) : .zero
            let next = CGPoint(x: route.position.x + move.x, y: route.position.y + move.y)
            route.feed(ScriptedRoute.Frame(still: !moving, line: line?(next)), move: move)
            if let stop, stop(route.last) { return true }
        }
        return false
    }

    /// The left-edge run, with the edge seen at `angle` (or marked by hand), then the first
    /// column's inward step: ends on column 1's up leg.
    private func columnOne(
        angle: Double, marked: Bool = false, follows: Bool = true, handedness: Double = 1,
        spacing: Double? = nil
    ) -> ScriptedRoute {
        let route = ScriptedRoute(fullCoverSlip: true, asksEdges: true) {
            $0.followsSlipTilt = follows
            if let spacing { $0.columnSpacingFields = spacing }
        }
        route.frameHandedness = handedness
        let left = CGPoint(x: -0.1, y: 0)
        route.feed(move: left, times: 10)
        if marked {
            route.feed(ScriptedRoute.Frame(still: true), times: 30)
            route.answer(.mark)
        } else {
            var offset = 1.0
            while offset >= 0.1 - 1e-9 {
                route.feed(ScriptedRoute.Frame(line: edgeLine(angle: angle, offset: offset)), move: left)
                offset -= 0.1
            }
            route.feed(
                ScriptedRoute.Frame(still: true, line: edgeLine(angle: angle, offset: 0.1)), times: 24)
            route.answer(.yes)
        }
        route.feed(move: CGPoint(x: 0.1, y: 0), times: 6)
        route.feed(ScriptedRoute.Frame(still: true), times: 14)
        route.feed(move: CGPoint(x: 0, y: -0.1), times: 8)
        return route
    }

    /// Where column 1's up leg puts spots over 14 fields, from the first one.
    private func upLegSpots(_ route: ScriptedRoute) -> [CGPoint] {
        let before = route.guide.placements.count
        drive(route, readings: 1500) { _ in route.guide.placements.count - before >= 17 }
        return route.guide.placements.dropFirst(before).map(\.position)
    }

    /// The columns' x against y: (x - x0) / (y - y0) for every spot, which must be -tan(angle).
    private func slopes(_ spots: [CGPoint]) -> [Double] {
        guard let first = spots.first else { return [] }
        return spots.dropFirst().map {
            Double($0.x - first.x) / Double($0.y - first.y)
        }
    }

    // MARK: Columns follow the slip's tilt

    func testPlusSevenDriftsAboutOnePointSevenOverFourteenFieldsKeepingTheEdgeDistance() throws {
        let route = columnOne(angle: 7)
        XCTAssertEqual(try XCTUnwrap(route.last.edge.slipTiltDegrees), 7, accuracy: 1e-9)
        let spots = upLegSpots(route)
        XCTAssertGreaterThanOrEqual(spots.count, 17)
        let first = try XCTUnwrap(spots.first)
        let last = try XCTUnwrap(spots.last)
        let along = Double(first.y - last.y)  // going up
        XCTAssertGreaterThan(along, 12)
        // The edge runs left going down (dx/dy = -tan 7), so going up the column moves right, by
        // along x tan 7: about 1.7 over 14 fields.
        XCTAssertEqual(Double(last.x - first.x), along * tan(7 * .pi / 180), accuracy: 0.05)
        XCTAssertGreaterThan(Double(last.x - first.x), 1.4)
        for slope in slopes(spots) { XCTAssertEqual(slope, -tan(7 * .pi / 180), accuracy: 0.02) }
    }

    func testAMinusSevenEdgeDriftsTheOtherWay() throws {
        let route = columnOne(angle: -7)
        XCTAssertEqual(try XCTUnwrap(route.last.edge.slipTiltDegrees), -7, accuracy: 1e-9)
        let spots = upLegSpots(route)
        let first = try XCTUnwrap(spots.first)
        let last = try XCTUnwrap(spots.last)
        XCTAssertEqual(
            Double(last.x - first.x), -Double(first.y - last.y) * tan(7 * .pi / 180), accuracy: 0.05)
        XCTAssertLessThan(Double(last.x - first.x), -1.4)
    }

    func testAMirroredFrameTurnsTheSignRound() throws {
        let route = columnOne(angle: 7, handedness: -1)
        XCTAssertEqual(try XCTUnwrap(route.last.edge.slipTiltDegrees), -7, accuracy: 1e-9)
        let spots = upLegSpots(route)
        XCTAssertLessThan(Double((spots.last?.x ?? 0) - (spots.first?.x ?? 0)), -1.4)
    }

    func testAHandMarkedLeftEdgeKeepsStraightColumns() {
        let route = columnOne(angle: 7, marked: true)
        XCTAssertNil(route.last.edge.slipTiltDegrees)
        let spots = upLegSpots(route)
        XCTAssertGreaterThanOrEqual(spots.count, 17)
        for slope in slopes(spots) { XCTAssertEqual(slope, 0, accuracy: 1e-6) }
    }

    func testTheToggleOffKeepsStraightColumns() {
        let route = columnOne(angle: 7, follows: false)
        XCTAssertNil(route.last.edge.slipTiltDegrees)
        for slope in slopes(upLegSpots(route)) { XCTAssertEqual(slope, 0, accuracy: 1e-6) }
    }

    func testAnAngleOverTheCapKeepsStraightColumns() {
        let route = columnOne(angle: 20)
        XCTAssertNil(route.last.edge.slipTiltDegrees)
        for slope in slopes(upLegSpots(route)) { XCTAssertEqual(slope, 0, accuracy: 1e-6) }
    }

    // MARK: A tilted early limit from column 1's top edge

    /// Column 1 up to a physical top edge at y = -5 leaning at `angle` (y = -5 + tan(a) (x - x1)),
    /// the answer yes at the cross, then a flat bottom edge at y = 3, then the step right (columns
    /// 4 fields apart so the tilt matters) and column 2 up. Returns the route, column 1's x and the
    /// spots column 2 placed.
    private func columnTwo(topAngle: Double) -> (ScriptedRoute, Double, [CGPoint]) {
        let route = columnOne(angle: 0, spacing: 4.0)
        let x1 = Double(route.position.x)
        let top = { (position: CGPoint) -> EdgeLine? in
            let edgeY = -5 + tan(topAngle * .pi / 180) * (Double(position.x) - x1)
            return self.edgeLine(angle: topAngle, offset: Double(position.y) - edgeY)
        }
        var asked = false
        drive(route, readings: 1500, line: top) { step in
            if step.instruction == .edgeDetected { asked = true }
            return asked
        }
        route.answer(.yes, ScriptedRoute.Frame(still: true, line: top(route.position)))
        let bottom = { (position: CGPoint) -> EdgeLine? in
            self.edgeLine(angle: 0, offset: 3 - Double(position.y))
        }
        asked = false
        drive(route, readings: 1500, line: bottom) { step in
            if step.instruction == .edgeDetected { asked = true }
            return asked
        }
        route.answer(.yes, ScriptedRoute.Frame(still: true, line: bottom(route.position)))
        drive(route, readings: 600) { $0.stateName == "column 2 up" }
        let before = route.guide.placements.count
        drive(route, readings: 3000) { _ in route.guide.placements.count - before >= 12 }
        let spots = route.guide.placements.filter { $0.column == 2 }.map(\.position)
        return (route, x1, spots)
    }

    func testColumnTwoStopsAtTheSixDegreeLineMinusTheMargin() throws {
        let (route, x1, spots) = columnTwo(topAngle: 6)
        XCTAssertEqual(route.last.edge.spotLimitReason, "tilted_prediction")
        let x2 = try XCTUnwrap(spots.first).x
        XCTAssertEqual(Double(x2) - x1, 4.0, accuracy: 0.15, "the spacing")
        let expected = -5 + tan(6 * .pi / 180) * (Double(x2) - x1) + 0.6
        XCTAssertEqual(Double(spots.map(\.y).min() ?? 0), expected, accuracy: 0.1, "\\(spots)")
    }

    func testAnAngleOverTwelveDegreesFallsBackToTheFlatLimit() throws {
        let (route, _, spots) = columnTwo(topAngle: 20)
        XCTAssertEqual(route.last.edge.spotLimitReason, "flat_prediction")
        XCTAssertEqual(Double(spots.map(\.y).min() ?? 0), -5 + 0.6, accuracy: 0.1, "\\(spots)")
    }

    // MARK: The stage's tilt reaches the guide before Start scan

    private struct AffineMapper: FrameToView {
        var transform: CGAffineTransform
        func viewPoint(of point: CGPoint) -> CGPoint { point.applying(transform) }
        func viewRect(of rect: CGRect) -> CGRect { rect.applying(transform) }
    }

    func testAStageAtTenDegreesStraightensTheGuidesAxesAndRestartsTheDryRun() throws {
        let stage = CentredFieldDemo.axes(tiltDegrees: 10)
        XCTAssertEqual(stage.tiltDegrees, 10, accuracy: 1e-6)
        let crop = CGRect(x: 380, y: 100, width: 520, height: 520)
        let centre = CGPoint(x: crop.midX, y: crop.midY)
        let view = CGSize(width: 400, height: 400)
        let frameBox = CGRect(x: 500, y: 220, width: 280, height: 280)
        func geometry(_ axes: StageAxes) throws -> GuideScreenGeometry {
            let display = FramePreviewConverter.displayTransform(
                crop: crop, centre: centre, straightening: axes.straightening, viewSize: view)
            return try XCTUnwrap(
                GuideGeometryHost.geometry(
                    using: AffineMapper(transform: display), box: frameBox, circle: nil))
        }
        let plain = try geometry(.identity)
        let straight = try geometry(stage)
        // A frame vector along the X knob lands on the screen's horizontal, the Y knob's on its
        // vertical: the guide's columns run along the stage's own Y and its step right along X.
        let along = straight.axes.screenVector(ofFrameVector: stage.xDirection)
        let down = straight.axes.screenVector(ofFrameVector: stage.yDirection)
        XCTAssertEqual(Double(along.y), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(Double(along.x), 0)
        XCTAssertEqual(Double(down.x), 0, accuracy: 1e-6)
        XCTAssertGreaterThan(Double(down.y), 0)
        // Unstraightened, the same vector is 10 degrees off.
        let tilted = plain.axes.screenVector(ofFrameVector: stage.xDirection)
        XCTAssertGreaterThan(abs(Double(tilted.y)), 0.1 * hypot(Double(tilted.x), Double(tilted.y)))
        // The geometry changed: `ScanEngine.setGuideGeometry` restarts the dry run (this happens
        // when the stage axes arrive, with the display transform the geometry host measures
        // through, not when the scan starts).
        XCTAssertFalse(plain.givesSamePositions(as: straight))
        // Skipped (identity axes): nothing changes.
        XCTAssertTrue(plain.givesSamePositions(as: try geometry(.identity)))
    }
}
