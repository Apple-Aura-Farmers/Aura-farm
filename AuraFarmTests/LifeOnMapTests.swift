import SwiftUI
import XCTest

@testable import AuraFarm

/// Phase 3b: where each counted organism goes on the map, its colour and legend, and the map kept
/// with the run.
@MainActor
final class LifeOnMapTests: XCTestCase {
    private let size = CGSize(width: 640, height: 480)
    private let fieldSide = 100.0

    private func detection(x: Double, y: Double) -> OrganismDetector.Detection {
        OrganismDetector.Detection(
            label: "Volvox", confidence: 0.9,
            box: CGRect(
                x: (x - 20) / 640, y: 1 - (y + 20) / 480, width: 40 / 640, height: 40 / 480))
    }

    /// The view travels along `step` (px a frame, tracker axes) past a stationary organism at
    /// slide point `q`: in frame `t` the tracker reads `t * step` and the organism shows at the
    /// frame centre plus `q + position`. Returns the counted entry and the trail (positions in
    /// fields) of every frame.
    private func pass(q: CGPoint, step: CGPoint, frames: Int = 40) -> (
        entry: SlideOrganismMap.Entry?, trail: [CGPoint]
    ) {
        var counter = LiveOrganismCounter()
        var trail: [CGPoint] = []
        for index in 0..<frames {
            let position = CGPoint(x: step.x * Double(index), y: step.y * Double(index))
            trail.append(CGPoint(x: position.x / fieldSide, y: position.y / fieldSide))
            counter.update(
                detections: [
                    detection(x: 320 + Double(q.x + position.x), y: 240 + Double(q.y + position.y))
                ],
                pictureMoved: index == 0 ? .zero : step, trackerPosition: position, frameSize: size,
                fieldCircle: nil, seconds: Double(index), column: 1, fieldSide: fieldSide)
        }
        return (counter.map.entries.first, trail)
    }

    func testAnOrganismAtTheFrameCentreLandsOnTheTrailPointOfThatFrame() {
        var counter = LiveOrganismCounter()
        let position = CGPoint(x: 230, y: -130)
        for _ in 0..<3 {
            counter.update(
                detections: [detection(x: 320, y: 240)], pictureMoved: .zero,
                trackerPosition: position, frameSize: size, fieldCircle: nil, seconds: 0, column: 1,
                fieldSide: fieldSide)
        }
        let entry = counter.map.entries.first
        XCTAssertEqual(Double(entry?.fields.x ?? .nan), 2.3, accuracy: 1e-9)
        XCTAssertEqual(Double(entry?.fields.y ?? .nan), -1.3, accuracy: 1e-9)
    }

    /// Both axes, both directions: the dot lies on the trail where the frame centre passed over
    /// the organism, within 0.05 field.
    func testAnOffCentreOrganismLandsWhereTheViewWouldHaveBeenCentredOnIt() throws {
        let cases: [(q: CGPoint, step: CGPoint)] = [
            (CGPoint(x: -150, y: 20), CGPoint(x: 10, y: 0)),  // x, travelling right
            (CGPoint(x: 150, y: -20), CGPoint(x: -10, y: 0)),  // x, travelling left
            (CGPoint(x: 30, y: -120), CGPoint(x: 0, y: 10)),  // y, travelling down
            (CGPoint(x: -30, y: 120), CGPoint(x: 0, y: -10)),  // y, travelling up
        ]
        for item in cases {
            let result = pass(q: item.q, step: item.step)
            let entry = try XCTUnwrap(result.entry, "\(item)")
            let dot = entry.fields
            let nearest =
                result.trail.map { hypot(Double($0.x - dot.x), Double($0.y - dot.y)) }.min() ?? .infinity
            // The trail passes within the organism's cross offset (20 or 30 px) of the dot along the
            // other axis, and exactly over it along the travel axis.
            let alongX = item.step.x != 0
            let across = abs(Double(alongX ? item.q.y : item.q.x)) / fieldSide
            XCTAssertEqual(nearest, across, accuracy: 0.05, "\(item)")
            XCTAssertEqual(Double(dot.x), -Double(item.q.x) / fieldSide, accuracy: 1e-9)
            XCTAssertEqual(Double(dot.y), -Double(item.q.y) / fieldSide, accuracy: 1e-9)
        }
    }

    func testARepeatOnTheMapIsNotDrawnTwice() {
        var counter = LiveOrganismCounter()
        for _ in 0..<5 {
            counter.update(
                detections: [detection(x: 200, y: 240)], pictureMoved: .zero, trackerPosition: .zero,
                frameSize: size, fieldCircle: nil, seconds: 0, column: 1, fieldSide: fieldSide)
        }
        for _ in 0..<100 {
            counter.update(
                detections: [], pictureMoved: .zero, trackerPosition: .zero, frameSize: size,
                fieldCircle: nil, seconds: 1, column: 1, fieldSide: fieldSide)
        }
        for _ in 0..<5 {
            counter.update(
                detections: [detection(x: 290, y: 240)], pictureMoved: .zero,
                trackerPosition: CGPoint(x: 90, y: 0), frameSize: size, fieldCircle: nil, seconds: 2,
                column: 2, fieldSide: fieldSide)
        }
        XCTAssertEqual(counter.map.entries.count, 1)
    }

    // MARK: Palette and legend

    func testTheSameLabelAlwaysGetsTheSameColourAndThereAreAtLeastEight() {
        XCTAssertGreaterThanOrEqual(OrganismPalette.colours.count, 8)
        let keys = OrganismPalette.colours.map { "\($0.red)-\($0.green)-\($0.blue)" }
        XCTAssertEqual(Set(keys).count, keys.count)
        // The first of V3's classes, which are the ones with a colour of their own: there are
        // more classes than colours, so the rest share the neutral grey.
        let coloured = ["Amoeba", "Arcellinida", "Ceratium", "Closterium", "Digononta"]
        for label in coloured {
            XCTAssertEqual(OrganismPalette.colour(for: label), OrganismPalette.colour(for: label))
            XCTAssertNotNil(OrganismPalette.index(for: label), label)
        }
        let known = coloured.compactMap(OrganismPalette.index(for:))
        XCTAssertEqual(Set(known).count, known.count, "every type has its own colour")
        XCTAssertNil(OrganismPalette.index(for: "background"), "the background slot is not a type")
    }

    func testATypeBeyondThePaletteIsNeutralGrey() {
        XCTAssertNil(OrganismPalette.index(for: "Paramecium"))
        XCTAssertEqual(OrganismPalette.colour(for: "Paramecium"), OrganismPalette.neutral)
        XCTAssertEqual(OrganismPalette.colour(for: "Stentor"), OrganismPalette.neutral)
    }

    func testTheLegendCountsEqualTheHelperCountsMostFirstAndOverflowsToMore() {
        let counts = ["Volvox": 7, "Nematode": 5, "Euglenoid": 5, "Arcellinida": 2, "Digononta": 0]
        let all = LifeLegend.rows(counts: counts)
        XCTAssertEqual(all.rows.map(\.label), ["Volvox", "Euglenoid", "Nematode", "Arcellinida"])
        XCTAssertEqual(all.rows.map(\.count), [7, 5, 5, 2])
        XCTAssertEqual(all.rows.reduce(0) { $0 + $1.count }, counts.values.reduce(0, +))
        XCTAssertEqual(all.more, 0)
        let top = LifeLegend.rows(counts: counts, limit: 3)
        XCTAssertEqual(top.rows.count, 3)
        XCTAssertEqual(top.more, 1)
    }

    // MARK: The map kept with the run

    private func record() -> GuideRunRecord {
        var record = GuideRunRecord(
            started: Date(timeIntervalSince1970: 1_700_000_000),
            ended: Date(timeIntervalSince1970: 1_700_000_300), finishReason: .rightEdge,
            spotMode: "brief_touch", coverageStep: 1.6, columns: 3, spotsTicked: 20, missedSpots: 2,
            elapsedSeconds: 300, secondsPerSpot: 15, coverageShare: 0.9,
            countsByLabel: ["Volvox": 3, "Nematode": 1], tallyCountsByLabel: ["Volvox": 4],
            totalCount: 4, minimumConfidence: 0.3, cropToEyepiece: true, classNames: ["Volvox"],
            framesCounted: 100, framesSkippedByReason: [:])
        for index in 0..<4 {
            let label = index == 0 ? "Nematode" : "Volvox"
            record.organisms.append(
                RunMapOrganism(
                    label: label, x: Double(index), y: Double(index) / 2, column: 1,
                    seconds: Double(index)))
        }
        for index in 0..<50 {
            record.path.append(RunMapPoint(x: Double(index) / 10, y: sin(Double(index) / 5)))
        }
        record.edges = [RunMapEdge(kind: "top", x1: 0, y1: -1, x2: 5, y2: -1)]
        record.mapMapping = ScreenMapping.rotateLeft.rawValue
        record.mapMirrored = true
        return record
    }

    func testARecordWithTheMapSurvivesAJSONRoundTrip() throws {
        let original = record()
        let data = try GuideRunRecord.encoder().encode(original)
        let decoded = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(RunMapContent(record: decoded).mapping, .rotateLeft)
        XCTAssertTrue(RunMapContent(record: decoded).mirrored)
    }

    func testARecordWithoutTheMapStillDecodes() throws {
        let old = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":0.8,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{},"tallyCountsByLabel":{},"totalCount":0,
            "minimumConfidence":0.3,"cropToEyepiece":false,"classNames":[],"framesCounted":1,
            "framesSkippedByReason":{}}
            """
        let decoded = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(old.utf8))
        XCTAssertTrue(decoded.organisms.isEmpty)
        XCTAssertTrue(decoded.path.isEmpty)
        XCTAssertTrue(decoded.edges.isEmpty)
        XCTAssertEqual(decoded.mapMapping, "asIs")
        XCTAssertFalse(decoded.mapMirrored)
        XCTAssertNil(RunMapContent(record: decoded).screenBounds)
    }

    func testThePathIsThinnedToTheLimitKeepingTheEnds() {
        let points = (0..<7000).map { CGPoint(x: Double($0), y: 0) }
        let thinned = RunMapContent.thinned(points)
        XCTAssertEqual(thinned.count, RunMapContent.maxPathPoints)
        XCTAssertEqual(thinned.first?.x, 0)
        XCTAssertEqual(thinned.last?.x, 6999)
        XCTAssertEqual(RunMapContent.thinned(Array(points.prefix(10))).count, 10)
    }

    func testTheSummaryMapRendersToANonEmptyPNG() throws {
        let data = try XCTUnwrap(RunMapExport.pngData(for: record()))
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47], "a PNG")
    }
}
