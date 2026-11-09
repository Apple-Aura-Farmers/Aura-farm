import AuraFarmKit
import SwiftData
import XCTest

@testable import AuraFarm

@MainActor
final class RecordsFromSweepsTests: XCTestCase {
    func testAFinishedSweepIsSavedToTheInboxWithItsCounts() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)

        let outcome = try importer.importSweep(Self.sweep(counts: ["Nematoda": 4, "Arcellinida": 9]))

        guard case .imported(let test) = outcome else {
            return XCTFail("Expected a new soil test, got \(outcome)")
        }
        XCTAssertEqual(test.sampleID, "A12")
        XCTAssertNil(test.field)
        XCTAssertEqual(test.totalCount, 13)
        XCTAssertEqual(test.preparation, SamplePreparation.summary)
    }

    func testSavingTheSameSweepAgainKeepsOneTest() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)
        let sweep = Self.sweep(counts: ["Nematoda": 4])

        _ = try importer.importSweep(sweep)
        let again = try importer.importSweep(sweep)

        guard case .alreadyImported = again else {
            return XCTFail("Expected the repeat to be recognised, got \(again)")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SoilTest>()), 1)
    }

    func testAddingThePhonesSweepsSkipsOnesThatWereNotCounted() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)
        let sweeps = [
            Self.sweep(counts: ["Nematoda": 4], name: "A12_f001_20261106-053000"),
            Self.sweep(counts: nil, name: "A12_f002_20261106-054000"),
            Self.sweep(counts: [:], name: "A12_f003_20261106-055000"),
        ]

        let summary = importer.importSweeps(sweeps)

        XCTAssertEqual(summary.imported, 2)
        XCTAssertTrue(summary.failures.isEmpty)
        XCTAssertEqual(importer.importSweeps(sweeps).duplicates, 2)
    }

    func testOnlyTheProgramManagerChangesRecords() {
        XCTAssertTrue(AppRole.programManager.canEditRecords)
        XCTAssertFalse(AppRole.fieldHelper.canEditRecords)
    }

    // MARK: - Fixtures

    private static func sweep(
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
