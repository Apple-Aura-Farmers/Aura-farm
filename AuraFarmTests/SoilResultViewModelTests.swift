import XCTest

@testable import AuraFarm

@MainActor
final class SoilResultViewModelTests: XCTestCase {
    /// A recommender that answers as told, and counts how often it was asked.
    private final class StubRecommender: RecommendationProviding {
        struct Failure: Error {}

        var availability: RecommenderAvailability = .available
        var fails = false
        private(set) var calls = 0

        func recommend(for result: SoilResult, estimate: SoilHealthEstimate) async throws -> Recommendation {
            calls += 1
            if fails { throw Failure() }
            return Recommendation(
                summary: "From the model", actions: ["One", "Two"], source: .foundationModel)
        }
    }

    private func result(_ counts: [String: Int]?) -> SoilResult {
        SoilResult(
            sampleID: "A12",
            recordedAt: .now,
            framesKept: 12,
            moisture: .drained,
            countsByClass: counts,
            sweep: nil
        )
    }

    private let fairCounts = ["paramecium": 9, "euglena": 6, "vorticella": 3]

    func testAvailableModelWritesTheAdvice() async {
        let stub = StubRecommender()
        let viewModel = SoilResultViewModel(result: result(fairCounts), recommender: stub)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.source, .foundationModel)
        XCTAssertNil(viewModel.modelUnavailableReason)
    }

    func testUnavailableModelFallsBackToStandardAdviceAndSaysWhy() async {
        let stub = StubRecommender()
        stub.availability = .unavailable(reason: "Off")
        let viewModel = SoilResultViewModel(result: result(fairCounts), recommender: stub)

        await viewModel.loadRecommendation()

        guard case .ready(let recommendation) = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(recommendation.source, .rules)
        XCTAssertEqual(viewModel.modelUnavailableReason, "Off")
        XCTAssertEqual(stub.calls, 0)
    }

    func testModelIsNotAskedAboutAnEmptySlide() async {
        let stub = StubRecommender()
        let viewModel = SoilResultViewModel(result: result([:]), recommender: stub)

        await viewModel.loadRecommendation()

        XCTAssertEqual(stub.calls, 0)
        XCTAssertEqual(
            viewModel.recommendationState, .ready(RuleBasedRecommender.recommendation(for: .tooFewToSay)))
    }

    func testFailureCanBeRetried() async {
        let stub = StubRecommender()
        stub.fails = true
        let viewModel = SoilResultViewModel(result: result(fairCounts), recommender: stub)

        await viewModel.loadRecommendation()
        guard case .failed = viewModel.recommendationState else {
            return XCTFail("Expected a failure, got \(viewModel.recommendationState)")
        }

        stub.fails = false
        await viewModel.loadRecommendation()
        guard case .ready = viewModel.recommendationState else {
            return XCTFail("Expected advice, got \(viewModel.recommendationState)")
        }
        XCTAssertEqual(stub.calls, 2)
    }

    func testBreakdownFollowsTheChosenTab() {
        let viewModel = SoilResultViewModel(result: result(fairCounts), recommender: StubRecommender())

        XCTAssertEqual(viewModel.breakdownRows.count, 3)
        viewModel.selectedTaxonomy = .organismGroup
        XCTAssertEqual(viewModel.breakdownRows.map(\.count), [12, 6])
    }
}
