import XCTest

@testable import AuraFarm

final class SampleDetailsTests: XCTestCase {
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    func testManifestFromBeforeFieldNotesStillDecodes() throws {
        let json = """
            {
              "byteCount" : 4096,
              "details" : {
                "field" : 2,
                "gramsOfSoil" : 10,
                "moisture" : "flooded",
                "recordedAt" : "2026-10-12T09:30:00Z",
                "sampleID" : "A12"
              },
              "frameCount" : 12,
              "organismCounts" : { "euglena" : 3 },
              "stoppedEarly" : false
            }
            """

        let manifest = try decoder.decode(SweepManifest.self, from: Data(json.utf8))

        XCTAssertEqual(manifest.details.sampleID, "A12")
        XCTAssertNil(manifest.details.plotName)
        XCTAssertNil(manifest.details.cropStage)
        XCTAssertNil(manifest.details.recentActions)
    }

    func testFieldNotesSurviveARoundTrip() throws {
        let details = SampleDetails(
            sampleID: "A12", field: 2, moisture: .drained, gramsOfSoil: 10, millilitresScanned: nil,
            recordedAt: Date(timeIntervalSince1970: 1_793_000_000), plotName: "North 2", cropStage: .fallow,
            recentActions: [.fertilized, .addedStraw])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try decoder.decode(SampleDetails.self, from: encoder.encode(details))

        XCTAssertEqual(decoded, details)
    }
}
