import XCTest

@testable import AuraFarm

/// Phase 4b part C: a guided scan keeps no frames, so abundance and the advice count fields of view.
final class GuidedScanAdviceTests: XCTestCase {
    private func result(
        total: Int = 76, frames: Int = 0, fields: Int? = 158
    ) -> SoilResult {
        SoilResult(
            sampleID: "A", recordedAt: .now, framesKept: frames, moisture: .drained,
            countsByClass: ["Nematode": total], fieldsScanned: fields)
    }

    private func context(_ result: SoilResult) -> AdviceContext {
        let estimate = SoilHealthEstimate(
            level: .fair, score: nil, confidence: .low, reasons: [], followUp: "Test again.")
        return AdviceContextBuilder().context(for: result, estimate: estimate, history: [])
    }

    func testSeventySixOrganismsOverOneFiftyEightFieldsIsAboutHalfPerField() {
        let guided = result()
        XCTAssertEqual(guided.viewsLooked, 158)
        XCTAssertTrue(guided.isGuidedScan)
        let perField = context(guided).interpretedPerFrame
        XCTAssertEqual(perField, 76.0 / 158.0, accuracy: 1e-9)
        XCTAssertEqual(perField, 0.48, accuracy: 0.01)
        XCTAssertLessThan(perField, 1, "not 76 per frame")
    }

    func testTheAdviceTextSaysFieldsOfViewScannedForAGuidedScan() {
        let prompt = AdvicePromptBuilder.prompt(for: context(result()))
        XCTAssertTrue(prompt.contains("Fields of view scanned: 158."))
        XCTAssertFalse(prompt.contains("Frames looked at"))
    }

    func testAFrameSweepIsUnchanged() {
        let frames = result(total: 76, frames: 12, fields: nil)
        XCTAssertFalse(frames.isGuidedScan)
        XCTAssertEqual(frames.viewsLooked, 12)
        XCTAssertEqual(context(frames).interpretedPerFrame, 76.0 / 12.0, accuracy: 1e-9)
        let prompt = AdvicePromptBuilder.prompt(for: context(frames))
        XCTAssertTrue(prompt.contains("Frames looked at: 12."))
        XCTAssertFalse(prompt.contains("Fields of view scanned"))
    }

    func testTheEstimateSaysPerFieldOfViewForAGuidedScan() {
        let estimate = PlaceholderSoilHealthEstimator().estimate(result())
        XCTAssertTrue(estimate.reasons.joined().contains("per field of view across 158 fields of view"))
        let old = PlaceholderSoilHealthEstimator().estimate(result(total: 76, frames: 12, fields: nil))
        XCTAssertTrue(old.reasons.joined().contains("per frame across 12 frames"))
    }

    func testAGuidedScanCarriesItsFieldsFromTheSavedManifest() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "fields-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var record = GuideRunRecord.previewForTests
        record.spotsTicked = 158
        let details = SampleDetails(
            sampleID: "A", location: "B", field: 1, moisture: .drained, gramsOfSoil: 10,
            millilitresScanned: nil, recordedAt: Date(timeIntervalSince1970: 1_793_176_205))
        let name = try GuidedScanSaver.save(
            details: details, record: record, movementCSV: nil, in: directory)
        let sweep = try XCTUnwrap(SweepLibrary.sweeps(in: directory).first { $0.name == name })
        XCTAssertEqual(sweep.manifest?.fieldsScanned, 158)
        let loaded = try SoilResult(sweep: sweep)
        XCTAssertEqual(loaded.viewsLooked, 158)
        // The report still says no frames were kept: its frame count is a count of frames.
        XCTAssertEqual(try SoilReportExporter.report(for: sweep).capture.frameCount, 0)
    }

    func testAnOldManifestWithoutFieldsStillDecodes() throws {
        let manifest = SweepManifest(
            details: SampleDetails(
                sampleID: "A", location: "B", field: 1, moisture: .drained, gramsOfSoil: 10,
                millilitresScanned: nil, recordedAt: .now), frameCount: 12, byteCount: 1,
            stoppedEarly: false, panoramaFile: nil, panoramaProblem: nil, organismCounts: [:])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var object =
            try JSONSerialization.jsonObject(with: encoder.encode(manifest)) as? [String: Any] ?? [:]
        object.removeValue(forKey: "fieldsScanned")
        object.removeValue(forKey: "guidedScan")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            SweepManifest.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.fieldsScanned)
        XCTAssertEqual(decoded.frameCount, 12)
    }
}
