import AuraFarmKit
import XCTest

@testable import AuraFarm

final class SoilReportExporterTests: XCTestCase {
    func testReportCarriesTheSampleAndCounts() throws {
        let sweep = makeSweep(counts: ["Nematoda": 4, "Arcellinida": 9, "Monogononta": 0])

        let report = try SoilReportExporter.report(for: sweep)

        XCTAssertEqual(report.sample.sampleID, "A12")
        XCTAssertEqual(report.sample.microscopeField, 2)
        XCTAssertEqual(report.sample.moisture, "flooded")
        XCTAssertEqual(report.sample.gramsOfSoil, 10)
        XCTAssertEqual(report.capture.frameCount, 12)
        XCTAssertEqual(report.capture.detectorModel, OrganismDetector.modelName)
        XCTAssertEqual(report.sample.millilitresOfWater, SamplePreparation.millilitresOfWater)
        XCTAssertEqual(report.sample.preparation, SamplePreparation.summary)
        // Most counted first; a group found zero times is left out.
        XCTAssertEqual(
            report.organisms,
            [
                SoilReport.OrganismCount(taxon: "Arcellinida", count: 9),
                SoilReport.OrganismCount(taxon: "Nematoda", count: 4),
            ]
        )
        XCTAssertEqual(report.totalCount, 13)
    }

    func testCountedButEmptySweepSendsNoOrganisms() throws {
        let report = try SoilReportExporter.report(for: makeSweep(counts: [:]))

        XCTAssertTrue(report.organisms.isEmpty)
    }

    func testSweepThatWasNotCountedCannotBeSent() {
        XCTAssertThrowsError(try SoilReportExporter.report(for: makeSweep(counts: nil))) { error in
            XCTAssertEqual(error as? SoilReportExporter.Failure, .notCounted)
        }
    }

    func testSweepWithoutDetailsCannotBeSent() {
        var sweep = makeSweep(counts: ["Nematoda": 1])
        sweep.manifest = nil

        XCTAssertThrowsError(try SoilReportExporter.report(for: sweep)) { error in
            XCTAssertEqual(error as? SoilReportExporter.Failure, .noSampleDetails)
        }
    }

    func testReportIDIsStableForASweepAndDiffersBetweenSweeps() {
        let first = makeSweep(counts: [:], name: "A12_f002_20261106-053000")
        let again = makeSweep(counts: [:], name: "A12_f002_20261106-053000")
        let other = makeSweep(counts: [:], name: "A12_f003_20261106-054500")

        XCTAssertEqual(SoilReportExporter.reportID(for: first), SoilReportExporter.reportID(for: again))
        XCTAssertNotEqual(SoilReportExporter.reportID(for: first), SoilReportExporter.reportID(for: other))
    }

    func testWrittenFileDecodesBackToTheReport() throws {
        let sweep = makeSweep(counts: ["Nematoda": 3])

        let url = try SoilReportExporter.writeTemporaryFile(for: sweep)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(url.pathExtension, SoilReport.fileExtension)
        let decoded = try SoilReportCodec.decode(Data(contentsOf: url))
        XCTAssertEqual(decoded.id, SoilReportExporter.reportID(for: sweep))
        XCTAssertEqual(decoded.totalCount, 3)
    }

    // MARK: Helpers

    private func makeSweep(
        counts: [String: Int]?,
        name: String = "A12_f002_20261106-053000"
    ) -> SavedSweep {
        let recordedAt = Date(timeIntervalSince1970: 1_793_943_000)
        let manifest = SweepManifest(
            details: SampleDetails(
                sampleID: "A12",
                field: 2,
                moisture: .flooded,
                gramsOfSoil: 10,
                millilitresScanned: 0.5,
                recordedAt: recordedAt
            ),
            frameCount: 12,
            byteCount: 4_096,
            stoppedEarly: false,
            organismCounts: counts
        )
        return SavedSweep(
            url: URL.temporaryDirectory.appending(path: name, directoryHint: .isDirectory),
            manifest: manifest,
            recordedAt: recordedAt,
            byteCount: 4_096,
            frameURLs: [],
            panoramaURL: nil
        )
    }
}
