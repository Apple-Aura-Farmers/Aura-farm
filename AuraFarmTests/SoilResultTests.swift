import XCTest

@testable import AuraFarm

final class SoilResultTests: XCTestCase {
    func testResultCarriesTheManifest() throws {
        let result = try SoilResult(sweep: makeSweep(counts: ["euglena": 3, "paramecium": 2, "volvox": 0]))

        XCTAssertEqual(result.sampleID, "A12")
        XCTAssertEqual(result.framesKept, 12)
        XCTAssertEqual(result.moisture, .flooded)
        XCTAssertEqual(result.totalCount, 5)
        XCTAssertEqual(result.classesFound, 2)
        XCTAssertNotNil(result.sweep)
    }

    func testSweepThatWasNotCountedHasNoTotal() throws {
        let result = try SoilResult(sweep: makeSweep(counts: nil))

        XCTAssertNil(result.totalCount)
        XCTAssertEqual(result.classesFound, 0)
    }

    func testSweepWithoutManifestHasNoResult() {
        var sweep = makeSweep(counts: [:])
        sweep.manifest = nil

        XCTAssertThrowsError(try SoilResult(sweep: sweep)) { error in
            XCTAssertEqual(error as? SoilResult.Failure, .noSampleDetails)
        }
    }

    private func makeSweep(counts: [String: Int]?) -> SavedSweep {
        let recordedAt = Date(timeIntervalSince1970: 1_793_943_000)
        return SavedSweep(
            url: URL.temporaryDirectory.appending(path: "A12_f002", directoryHint: .isDirectory),
            manifest: SweepManifest(
                details: SampleDetails(
                    sampleID: "A12",
                    field: 2,
                    moisture: .flooded,
                    gramsOfSoil: 1,
                    millilitresScanned: nil,
                    recordedAt: recordedAt
                ),
                frameCount: 12,
                byteCount: 4_096,
                stoppedEarly: false,
                organismCounts: counts
            ),
            recordedAt: recordedAt,
            byteCount: 4_096,
            frameURLs: [],
            panoramaURL: nil
        )
    }
}
