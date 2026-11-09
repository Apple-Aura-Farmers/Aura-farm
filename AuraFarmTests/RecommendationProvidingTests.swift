import XCTest

@testable import AuraFarm

final class RecommendationProvidingTests: XCTestCase {
    private final class Recorder: RecommendationProviding, @unchecked Sendable {
        var availability: RecommenderAvailability { .available }
        private(set) var freshRequests: [Bool] = []
        private(set) var reported: [AdviceProgress] = []

        func recommend(
            for context: AdviceContext, freshWording: Bool,
            onProgress: @escaping @Sendable (AdviceProgress) -> Void
        ) async throws -> Recommendation {
            freshRequests.append(freshWording)
            onProgress(.noticing)
            return RuleBasedRecommender.recommendation(for: context)
        }
    }

    func testTheShortFormAsksForTheSameWordingAndIgnoresProgress() async throws {
        let result = SoilResult(
            sampleID: "A12", recordedAt: .now, framesKept: 12, moisture: .flooded,
            countsByClass: ["paramecium": 9, "euglena": 6], sweep: nil)
        let context = AdviceContextBuilder().context(
            for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])
        let recorder = Recorder()

        _ = try await recorder.recommend(for: context)

        XCTAssertEqual(recorder.freshRequests, [false])
    }

    func testPrewarmDoesNothingByDefault() {
        Recorder().prewarm()
        RuleBasedRecommender().prewarm()
    }
}
