import AuraFarmKit
import SwiftData
import XCTest

@testable import AuraFarm

@MainActor
final class SoilReportImporterTests: XCTestCase {
    func testImportFilesTheTestInTheInboxWithItsCounts() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)

        let outcome = try importer.importReport(Self.makeReport())

        guard case .imported(let test) = outcome else {
            return XCTFail("Expected a new soil test, got \(outcome)")
        }
        XCTAssertEqual(test.sampleID, "A12")
        XCTAssertEqual(test.moistureLabel, "Flooded")
        XCTAssertNil(test.field)
        XCTAssertEqual(test.placeLabel, "Unassigned")
        XCTAssertEqual(test.totalCount, 12)
        XCTAssertEqual(test.sortedCounts.map(\.taxon), ["Nematoda", "Arcellinida"])
    }

    func testTheSameReportTwiceKeepsOneTest() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)
        let report = Self.makeReport()

        _ = try importer.importReport(report)
        let second = try importer.importReport(report)

        guard case .alreadyImported = second else {
            return XCTFail("Expected the repeat to be recognised, got \(second)")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SoilTest>()), 1)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<OrganismCount>()), 2)
    }

    func testImportReadsAReportFile() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).aurafarm")
        try SoilReportCodec.encode(Self.makeReport()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let outcome = try importer.importReport(at: url)

        guard case .imported(let test) = outcome else {
            return XCTFail("Expected a new soil test, got \(outcome)")
        }
        XCTAssertEqual(test.frameCount, 12)
    }

    func testAFileThatIsNotAReportIsRejected() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let importer = SoilReportImporter(context: container.mainContext)
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).aurafarm")
        try Data("not a report".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try importer.importReport(at: url)) { error in
            XCTAssertEqual(error as? SoilReportCodec.Failure, .notASoilReport)
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<SoilTest>()), 0)
    }

    func testDeletingAFieldSendsItsTestsBackToTheInbox() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let importer = SoilReportImporter(context: context)
        guard case .imported(let test) = try importer.importReport(Self.makeReport()) else {
            return XCTFail("Expected a new soil test")
        }
        let farm = Farm(name: "Pak Made")
        let field = Field(name: "North paddy")
        context.insert(farm)
        context.insert(field)
        field.farm = farm
        test.field = field
        try context.save()
        XCTAssertEqual(test.placeLabel, "Pak Made · North paddy")
        XCTAssertEqual(farm.soilTests.count, 1)

        context.delete(field)
        try context.save()

        XCTAssertNil(test.field)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SoilTest>()), 1)
    }

    func testImportSummaryNamesWhatHappened() {
        XCTAssertEqual(ImportSummary(imported: 2).title, "Imported 2 soil tests")
        XCTAssertEqual(ImportSummary(duplicates: 1).title, "Already imported")
        let failure = ImportSummary.Failure(fileName: "a.aurafarm", reason: "Damaged.")
        XCTAssertEqual(ImportSummary(failures: [failure]).title, "Nothing was imported")
    }

    private static func makeReport() -> SoilReport {
        let recordedAt = Date(timeIntervalSince1970: 1_793_943_000)
        return SoilReport(
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
            ]
        )
    }
}
