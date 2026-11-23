import AuraFarmKit
import XCTest

@testable import AuraFarm

final class SoilResultUploaderTests: XCTestCase {
    func testThePanoramaDoesNotRideAlongInTheJSONColumn() throws {
        // A real panorama is megabytes. Base64 of it in a jsonb column would make every
        // later read of the row carry the picture.
        let picture = Data(repeating: 0xAB, count: 4096)
        let row = ResultRow(report: report(panoramaJPEG: picture), sampleID: UUID())

        let encoded = try JSONEncoder().encode(row)

        XCTAssertNil(row.report.panoramaJPEG)
        let sent = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(sent.contains(picture.base64EncodedString()))
    }

    private func pictures(_ count: Int) -> [OrganismPicture] {
        (0..<count).map {
            OrganismPicture(
                image: .init(taxon: "Volvox", path: "id/organism-\($0).jpg"),
                file: URL(filePath: "/tmp/\($0).jpg"))
        }
    }

    private actor Sent {
        private(set) var paths: [String] = []
        private(set) var most = 0
        private var now = 0
        func begin() {
            now += 1
            most = max(most, now)
        }
        func end(_ path: String) {
            now -= 1
            paths.append(path)
        }
    }

    func testEveryPictureIsSentAFewAtATime() async throws {
        let sent = Sent()
        let all = pictures(11)
        try await SoilResultUploader.send(all, atOnce: 4) { picture in
            await sent.begin()
            try await Task.sleep(for: .milliseconds(5))
            await sent.end(picture.image.path)
        }
        let paths = await sent.paths
        let most = await sent.most
        XCTAssertEqual(Set(paths), Set(all.map(\.image.path)))
        XCTAssertEqual(paths.count, 11)
        XCTAssertLessThanOrEqual(most, 4)
    }

    func testAPictureThatFailsDoesNotStopTheOthersAndIsReported() async {
        struct Refused: LocalizedError { var errorDescription: String? { "Bucket not found" } }
        let sent = Sent()
        do {
            try await SoilResultUploader.send(pictures(5), atOnce: 2) { picture in
                if picture.image.path.hasSuffix("-1.jpg") { throw Refused() }
                await sent.begin()
                await sent.end(picture.image.path)
            }
            XCTFail("a missing picture must be said")
        } catch {
            XCTAssertTrue(
                error.localizedDescription.hasPrefix(
                    "The result was sent, but 1 of its 5 pictures were not."),
                error.localizedDescription)
            XCTAssertTrue(error.localizedDescription.contains("Bucket not found"))
        }
        let count = await sent.paths.count
        XCTAssertEqual(count, 4)
    }

    func testNoPicturesSendNothing() async throws {
        try await SoilResultUploader.send([]) { _ in XCTFail("nothing to send") }
    }

    func testTheColumnsAreNamedTheWayThePostgresTableIs() throws {
        let row = ResultRow(report: report(), sampleID: UUID())

        let json =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(row)) as? [String: Any]

        XCTAssertEqual(
            Set(json?.keys ?? [:].keys),
            [
                "id", "sample_id", "grams_of_soil", "millilitres_scanned",
                "millilitres_of_water", "frame_count", "detector_model", "recorded_at",
                "report",
            ]
        )
    }

    func testTheRowRepeatsWhatTheManagerFiltersOnAndLeavesTheRestInTheReport() throws {
        let row = ResultRow(report: report(), sampleID: UUID())

        XCTAssertEqual(row.frameCount, 12)
        XCTAssertEqual(row.detectorModel, "best-5")
        XCTAssertEqual(row.gramsOfSoil, 4)
        XCTAssertEqual(row.millilitresOfWater, 20)
        // Not columns of its own, so they are only readable through the json.
        XCTAssertEqual(row.report.sample.moisture, "drained")
        XCTAssertEqual(row.report.capture.stoppedEarly, false)
    }

    func testEveryLabelTheShippingDetectorEmitsHasAnEnumValue() {
        // the detector's class list, less the background slot. A label with no value here
        // would be dropped from the counts table without anyone noticing.
        for label in ["Arcellinida", "Digononta", "Euglenoid", "Nematode", "Volvox"] {
            XCTAssertNotNil(MicroorganismRow.storedTaxa[label], label)
        }
    }

    func testAGroupTheEnumHasNoValueForIsLeftOutRatherThanFailingTheUpload() {
        // Postgres rejects the whole insert for one unknown label, and the count is still in
        // the report json, so the row is dropped instead.
        let rows = MicroorganismRow.rows(
            for: report(organisms: [
                SoilReport.OrganismCount(taxon: "Monogononta", count: 9),
                SoilReport.OrganismCount(taxon: "Volvox", count: 2),
            ]))

        XCTAssertEqual(rows.map(\.type), ["Volvox"])
    }

    func testTheOlderNematodeSpellingIsFoldedInRatherThanColliding() {
        // Both spellings mean the same animal, and the table's key is the result and the
        // type, so two rows of it would be rejected.
        let rows = MicroorganismRow.rows(
            for: report(organisms: [
                SoilReport.OrganismCount(taxon: "Nematoda", count: 3),
                SoilReport.OrganismCount(taxon: "Nematode", count: 4),
            ]))

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.type, "Nematode")
        XCTAssertEqual(rows.first?.count, 7)
    }

    func testTheCountRowsAreNamedTheWayThePostgresTableIs() throws {
        let rows = MicroorganismRow.rows(for: report())

        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(rows))
        let first = (json as? [[String: Any]])?.first

        XCTAssertEqual(Set(first?.keys ?? [:].keys), ["result_id", "type", "count"])
    }

    // MARK: Helpers

    private func report(
        panoramaJPEG: Data? = nil,
        organisms: [SoilReport.OrganismCount] = [
            SoilReport.OrganismCount(taxon: "Nematode", count: 3)
        ]
    ) -> SoilReport {
        SoilReport(
            id: UUID(),
            createdAt: .now,
            sample: SoilReport.Sample(
                sampleID: "A12",
                microscopeField: 1,
                moisture: "drained",
                gramsOfSoil: 4,
                millilitresScanned: 1,
                millilitresOfWater: 20,
                recordedAt: .now
            ),
            capture: SoilReport.Capture(
                frameCount: 12,
                stoppedEarly: false,
                detectorModel: "best-5",
                appVersion: "0.1.0 (1)"
            ),
            organisms: organisms,
            panoramaJPEG: panoramaJPEG
        )
    }
}
