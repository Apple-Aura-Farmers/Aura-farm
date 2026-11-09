import XCTest

@testable import AuraFarm

final class SavedAdviceTests: XCTestCase {
    private let recommendation = Recommendation(
        summary: "Some soil life was seen.", noticed: ["Three kinds were seen."],
        steps: [
            Recommendation.Step(
                actionID: .resampleLater, text: "Sample again.", why: "One sample can vary.",
                timing: "2 to 4 weeks"),
            Recommendation.Step(actionID: nil, text: "Run the sweep again.", why: nil, timing: nil),
        ],
        source: .foundationModel)

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }

    func testARecommendationSurvivesARoundTrip() throws {
        XCTAssertEqual(try roundTrip(recommendation), recommendation)
    }

    func testSavedAdviceSurvivesARoundTrip() throws {
        let saved = SavedAdvice(
            recommendation: recommendation, writtenAt: Date(timeIntervalSince1970: 1_800_000_000),
            contentVersion: AdviceContentVersion.current, appVersion: "1.2")

        XCTAssertEqual(try roundTrip(saved), saved)
    }

    func testAnUnknownActionIDBecomesNilAndTheTextIsKept() throws {
        let json = """
            {"actionID": "plant_trees", "text": "Plant trees.", "why": "Shade.", "timing": "Now"}
            """

        let step = try JSONDecoder().decode(Recommendation.Step.self, from: Data(json.utf8))

        XCTAssertNil(step.actionID)
        XCTAssertEqual(step.text, "Plant trees.")
        XCTAssertEqual(step.why, "Shade.")
        XCTAssertEqual(step.timing, "Now")
    }

    func testAMissingActionIDAlsoDecodes() throws {
        let step = try JSONDecoder().decode(
            Recommendation.Step.self, from: Data(#"{"text": "Run the sweep again."}"#.utf8))

        XCTAssertNil(step.actionID)
        XCTAssertNil(step.why)
    }

    func testOlderRulesAreRecognised() {
        var saved = SavedAdvice(
            recommendation: recommendation, writtenAt: .now, contentVersion: AdviceContentVersion.current,
            appVersion: nil)
        XCTAssertFalse(saved.isFromOlderRules)

        saved.contentVersion = "2026-01-01-old"
        XCTAssertTrue(saved.isFromOlderRules)
    }
}
