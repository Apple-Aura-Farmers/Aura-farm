//
//  AdviceSnapshotTests.swift
//  AuraFarmTests
//
//  Created by William Silvano Angga on 13/11/26.
//

import XCTest

@testable import AuraFarm

final class AdviceSnapshotTests: XCTestCase {
    private let recordedAt = Date(timeIntervalSince1970: 1_800_000_000)

    private func context(soil: SoilMeasurements?, history: Int = 0) -> AdviceContext {
        let result = SoilResult(
            sampleID: "A12", recordedAt: recordedAt, framesKept: 12, moisture: .flooded,
            countsByClass: ["paramecium": 9, "euglena": 6, "vorticella": 3], sweep: nil, soil: soil)
        let past = PastResult(
            recordedAt: .distantPast, moisture: .flooded, cropStage: nil, organismsPerFrame: 1,
            interpretedKinds: 2, level: .fair)
        return AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result),
            history: Array(repeating: past, count: history))
    }

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    private let recommendation = Recommendation(
        summary: "Some soil life was seen.", noticed: [],
        steps: [Recommendation.Step(actionID: .keepNotes, text: "Write it down.", why: nil, timing: "Now")],
        source: .foundationModel)

    func testItCopiesWhatTheAdviceWasBasedOn() {
        let soil = SoilMeasurements(nitrogen: 100, ph: 6.5, fertilizerProduct: "Urea")

        let snapshot = AdviceSnapshot(context: context(soil: soil, history: 2))

        XCTAssertEqual(snapshot.sampleID, "A12")
        XCTAssertEqual(snapshot.testRecordedAt, recordedAt)
        XCTAssertEqual(snapshot.earlierSamples, 2)
        XCTAssertEqual(snapshot.soil, SoilInputs(nitrogen: 100, ph: 6.5))
    }

    func testNoMeasurementsIsAnEmptySnapshotValue() {
        XCTAssertNil(AdviceSnapshot(context: context(soil: nil)).soil)
        XCTAssertNil(AdviceSnapshot(context: context(soil: SoilMeasurements())).soil)
    }

    func testSavedAdviceKeepsItsSnapshotThroughARoundTrip() throws {
        let saved = SavedAdvice(
            recommendation: recommendation, writtenAt: recordedAt,
            contentVersion: AdviceContentVersion.current, appVersion: "1.0",
            snapshot: AdviceSnapshot(context: context(soil: SoilMeasurements(ph: 6.5))))

        XCTAssertEqual(try roundTrip(saved), saved)
    }

    /// Advice saved before snapshots existed has no `snapshot` key and still opens.
    func testAdviceSavedBeforeSnapshotsStillLoads() throws {
        let old = SavedAdvice(
            recommendation: recommendation, writtenAt: recordedAt,
            contentVersion: AdviceContentVersion.current, appVersion: nil)
        let json = try JSONEncoder().encode(old)
        XCTAssertFalse(String(decoding: json, as: UTF8.self).contains("snapshot"))

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let loaded = try decoder.decode(SavedAdvice.self, from: encoder.encode(old))

        XCTAssertNil(loaded.snapshot)
        XCTAssertEqual(loaded, old)
    }
}
