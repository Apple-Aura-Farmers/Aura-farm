import XCTest

@testable import AuraFarm

final class GuideRunRecordTests: XCTestCase {
    private func record(_ reason: SweepFinishReason = .rightEdge, share: Double? = 0.75) -> GuideRunRecord {
        GuideRunRecord(
            started: Date(timeIntervalSince1970: 1_700_000_000),
            ended: Date(timeIntervalSince1970: 1_700_000_300), finishReason: reason,
            spotMode: "brief_touch", coverageStep: 1.6, columns: 3, spotsTicked: 20, missedSpots: 2,
            elapsedSeconds: 300, secondsPerSpot: 15, coverageShare: share,
            countsByLabel: ["Volvox": 7], tallyCountsByLabel: ["Volvox": 9], totalCount: 7,
            minimumConfidence: 0.3, cropToEyepiece: false, classNames: ["Volvox"], framesCounted: 100,
            framesSkippedByReason: ["too_fast": 12])
    }

    func testARunRecordSurvivesAJSONRoundTrip() throws {
        let original = record()
        let data = try GuideRunRecord.encoder().encode(original)
        XCTAssertEqual(try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data), original)
    }

    func testTheLensVideoFieldsSurviveARoundTripAndOldRecordsHaveNone() throws {
        var original = record()
        original.lensVideoFile = "lens-20261119-120000.mov"
        original.lensVideoScanStartSeconds = 41.5
        let data = try GuideRunRecord.encoder().encode(original)
        let back = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data)
        XCTAssertEqual(back, original)
        XCTAssertEqual(back.lensVideoFile, "lens-20261119-120000.mov")
        XCTAssertEqual(back.lensVideoScanStartSeconds, 41.5)
        let plain = try GuideRunRecord.decoder().decode(
            GuideRunRecord.self, from: GuideRunRecord.encoder().encode(record()))
        XCTAssertNil(plain.lensVideoFile)
        XCTAssertNil(plain.lensVideoScanStartSeconds)
    }

    func testEveryFinishReasonHasItsCardTitle() {
        XCTAssertEqual(record(.endedByHelper).title, "Ended early")
        XCTAssertEqual(record(.stageLimit).title, "Stage limit")
        XCTAssertEqual(record(.rightEdge).title, "Reached the right edge")
        XCTAssertEqual(record(.sampleFinished).title, "Finished")
        XCTAssertEqual(record(.storageFull).title, "Finished")
    }

    func testANilCoverageShareShowsAsUnknown() {
        XCTAssertEqual(record(share: nil).coverageText, "unknown")
        XCTAssertEqual(record(share: 0.754).coverageText, "75%")
        XCTAssertNil(GuideRunRecord.coverageShare(columns: 3, step: 0.8, edgeSpanFields: nil))
        XCTAssertEqual(
            GuideRunRecord.coverageShare(columns: 3, step: 0.8, edgeSpanFields: 4.8) ?? 0, 0.5, accuracy: 1e-9
        )
        XCTAssertEqual(GuideRunRecord.coverageShare(columns: 9, step: 0.8, edgeSpanFields: 2) ?? 0, 1)
    }

    func testAFullCoverRunKnowsItsEdgeSpan() {
        let drop = SimulatedDrop(circles: [], rects: [CGRect(x: 0, y: 0, width: 2.8, height: 2.4)])
        let simulator = GuideSimulator(drop: drop, start: CGPoint(x: 1.5, y: 1.2))
        simulator.useFullCoverSlip()
        _ = simulator.run()
        let span = simulator.guide.edgeSpanFields
        XCTAssertNotNil(span)
        XCTAssertEqual(span ?? 0, 2.8, accuracy: 0.6)
    }

    func testARecordFromBeforeTheDetectorModelWasSavedStillDecodes() throws {
        let old = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":0.8,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{"Volvox":7},"tallyCountsByLabel":{"Volvox":9},
            "totalCount":7,"minimumConfidence":0.3,"cropToEyepiece":false,"classNames":["Volvox"],
            "framesCounted":100,"framesSkippedByReason":{"too_fast":12}}
            """
        let record = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(old.utf8))
        XCTAssertEqual(record.detectorModel, "v1")
        XCTAssertEqual(record.discDrops, 0)
        XCTAssertEqual(record.bigDrops, 0)
        XCTAssertEqual(record.detectorUnits, "gpu", "earlier records ran on the graphics chip")
        XCTAssertNil(record.secondsPerSpot)
        XCTAssertEqual(record.totalCount, 7)
    }

    func testTheModelAndDropsRoundTrip() throws {
        var original = record()
        original.detectorModel = "v2"
        original.discDrops = 4
        original.bigDrops = 2
        original.detectorUnits = "ne"
        let data = try GuideRunRecord.encoder().encode(original)
        XCTAssertEqual(try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data), original)
    }

    func testAnOrganismsPictureNameRoundTripsAndOldOrganismsWithoutOneStillDecode() throws {
        var original = record()
        original.organisms = [
            RunMapOrganism(
                label: "Volvox", x: 1, y: 2, column: 1, seconds: 3, image: "organism-007.jpg"),
            RunMapOrganism(label: "Paramecium", x: 4, y: 5, column: 2, seconds: 6),
        ]
        let data = try GuideRunRecord.encoder().encode(original)
        let back = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data)
        XCTAssertEqual(back, original)
        XCTAssertEqual(back.organisms.first?.image, "organism-007.jpg")
        XCTAssertNil(back.organisms.last?.image)

        let old = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":0.8,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{"Volvox":7},"tallyCountsByLabel":{"Volvox":9},
            "totalCount":7,"minimumConfidence":0.3,"cropToEyepiece":false,"classNames":["Volvox"],
            "framesCounted":100,"framesSkippedByReason":{"too_fast":12},
            "organisms":[{"label":"Volvox","x":1,"y":2,"column":1,"seconds":3}]}
            """
        let record = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(old.utf8))
        XCTAssertEqual(record.organisms.count, 1)
        XCTAssertNil(record.organisms[0].image)
    }

    func testTheStageObjectiveAndPathRoundTripAndOldRecordsAreManual() throws {
        var original = record()
        original.stage = "terraloka"
        original.objective = "100x"
        original.pathMode = "presetPath"
        let data = try GuideRunRecord.encoder().encode(original)
        let back = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: data)
        XCTAssertEqual(back, original)
        XCTAssertEqual(back.stageLine, "Terraloka Stage · 100x · Fixed sweep")
        original.pathMode = "followGuide"
        original.objective = "40x"
        XCTAssertEqual(original.stageLine, "Terraloka Stage · 40x · Follow the guide")

        let old = """
            {"started":"2026-11-16T15:47:00Z","ended":"2026-11-16T15:52:00Z","finishReason":"rightEdge",
            "spotMode":"brief_touch","coverageStep":0.8,"columns":3,"spotsTicked":20,"missedSpots":1,
            "elapsedSeconds":300,"countsByLabel":{"Volvox":7},"tallyCountsByLabel":{"Volvox":9},
            "totalCount":7,"minimumConfidence":0.3,"cropToEyepiece":false,"classNames":["Volvox"],
            "framesCounted":100,"framesSkippedByReason":{"too_fast":12}}
            """
        let decoded = try GuideRunRecord.decoder().decode(GuideRunRecord.self, from: Data(old.utf8))
        XCTAssertEqual(decoded.stage, "manual")
        XCTAssertNil(decoded.objective)
        XCTAssertNil(decoded.pathMode)
        XCTAssertEqual(decoded.stageLine, "Manual Stage")
    }
}
