import XCTest

@testable import AuraFarmKit

final class SoilReportCodecTests: XCTestCase {
    func testRoundTripKeepsEveryField() throws {
        let report = Self.makeReport(panorama: Data([0xFF, 0xD8, 0xFF]))

        let decoded = try SoilReportCodec.decode(SoilReportCodec.encode(report))

        XCTAssertEqual(decoded, report)
    }

    func testTotalCountAddsEveryGroup() {
        XCTAssertEqual(Self.makeReport().totalCount, 12)
    }

    func testReportWithoutPanoramaStillDecodes() throws {
        let report = Self.makeReport(panorama: nil)

        let decoded = try SoilReportCodec.decode(SoilReportCodec.encode(report))

        XCTAssertNil(decoded.panoramaJPEG)
    }

    func testNewerSchemaVersionIsNamedAsSuch() throws {
        var report = Self.makeReport()
        report.schemaVersion = SoilReport.currentSchemaVersion + 1
        let data = try SoilReportCodec.encode(report)

        XCTAssertThrowsError(try SoilReportCodec.decode(data)) { error in
            XCTAssertEqual(
                error as? SoilReportCodec.Failure,
                .newerSchemaVersion(SoilReport.currentSchemaVersion + 1)
            )
        }
    }

    func testOtherJSONIsNotASoilReport() {
        let data = Data(#"{"hello": "world"}"#.utf8)

        XCTAssertThrowsError(try SoilReportCodec.decode(data)) { error in
            XCTAssertEqual(error as? SoilReportCodec.Failure, .notASoilReport)
        }
    }

    func testDamagedReportIsNotASoilReport() throws {
        let data = try SoilReportCodec.encode(Self.makeReport())
        let truncated = data.prefix(data.count / 2)

        XCTAssertThrowsError(try SoilReportCodec.decode(Data(truncated))) { error in
            XCTAssertEqual(error as? SoilReportCodec.Failure, .notASoilReport)
        }
    }

    func testSuggestedFileNameIsSafeAndDated() {
        var report = Self.makeReport()
        report.sample.sampleID = " A/12 "

        XCTAssertEqual(report.suggestedFileName, "A-12 2026-11-06.aurafarm")
    }

    func testSuggestedFileNameFallsBackWhenThereIsNoID() {
        var report = Self.makeReport()
        report.sample.sampleID = "   "

        XCTAssertEqual(report.suggestedFileName, "Sample 2026-11-06.aurafarm")
    }

    func testKnownTaxaHaveCommonNamesAndUnknownOnesPassThrough() {
        XCTAssertEqual(OrganismGroup.commonName(forTaxon: "Nematoda"), "Nematodes")
        XCTAssertEqual(OrganismGroup.commonName(forTaxon: "Tardigrada"), "Tardigrada")
    }

    /// 2026-11-06 05:30 UTC.
    private static let recordedAt = Date(timeIntervalSince1970: 1_793_943_000)

    private static func makeReport(panorama: Data? = nil) -> SoilReport {
        SoilReport(
            id: UUID(uuidString: "6F1C2B0A-5D7E-4C1A-9B3E-2A4D6E8F0B1C")!,
            createdAt: recordedAt.addingTimeInterval(600),
            sample: SoilReport.Sample(
                sampleID: "A12",
                microscopeField: 1,
                moisture: "flooded",
                gramsOfSoil: 10,
                millilitresScanned: 0.5,
                recordedAt: recordedAt
            ),
            capture: SoilReport.Capture(
                frameCount: 12,
                stoppedEarly: false,
                detectorModel: "SoilDetector",
                appVersion: "0.1.0 (1)"
            ),
            organisms: [
                SoilReport.OrganismCount(taxon: "Nematoda", count: 7),
                SoilReport.OrganismCount(taxon: "Arcellinida", count: 5),
            ],
            panoramaJPEG: panorama
        )
    }
}
