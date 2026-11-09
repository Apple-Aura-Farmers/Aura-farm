#if DEBUG
    import XCTest

    @testable import AuraFarm

    final class ResultScenarioTests: XCTestCase {
        func testLiveModelReplacesEveryStubExceptTheProblemOnes() {
            for scenario in ResultScenario.allCases {
                let recommender = scenario.recommender(useLiveModel: true)
                if scenario.simulatesModelProblem {
                    XCTAssertTrue(recommender is ScenarioRecommender, scenario.rawValue)
                } else {
                    XCTAssertTrue(recommender is FoundationModelRecommender, scenario.rawValue)
                }
            }
        }

        func testWithoutTheLiveModelOnlyLiveModelAsksTheRealModel() {
            for scenario in ResultScenario.allCases {
                let recommender = scenario.recommender(useLiveModel: false)
                if scenario == .liveModel {
                    XCTAssertTrue(recommender is FoundationModelRecommender)
                } else {
                    XCTAssertTrue(recommender is ScenarioRecommender, scenario.rawValue)
                }
            }
        }

        func testProblemScenarios() {
            XCTAssertEqual(
                ResultScenario.allCases.filter(\.simulatesModelProblem),
                [
                    .missingDetails, .modelUnavailable, .modelFails, .modelSlow, .modelBlocked, .modelBusy,
                    .modelWritesBannedWord, .modelBreaksSeveralRules, .modelPicksBadIDs, .savedAdvice,
                ])
        }

        func testTheSavedAdviceScenarioKeepsItsStubAndHasOlderSavedAdvice() throws {
            let scenario = ResultScenario.savedAdvice
            XCTAssertTrue(scenario.simulatesModelProblem)
            XCTAssertTrue(scenario.recommender(useLiveModel: true) is ScenarioRecommender)

            let sweep = try XCTUnwrap(scenario.result?.sweep)
            let saved = try XCTUnwrap(scenario.adviceStore.load(for: sweep))
            XCTAssertEqual(saved.contentVersion, "2026-01-01-old")
            XCTAssertTrue(saved.isFromOlderRules)
            XCTAssertFalse(FileManager.default.fileExists(atPath: sweep.url.path))
        }

        func testOtherScenariosHaveNoSweepAndNothingSaved() {
            for scenario in ResultScenario.allCases where scenario != .savedAdvice {
                XCTAssertNil(scenario.result?.sweep, scenario.rawValue)
            }
        }

        func testModelFailureScenariosKeepTheirStubWhenTheLiveModelIsOn() {
            let scenarios: [ResultScenario] = [
                .modelBlocked, .modelBusy, .modelWritesBannedWord, .modelBreaksSeveralRules,
                .modelPicksBadIDs,
            ]
            for scenario in scenarios {
                XCTAssertTrue(scenario.simulatesModelProblem, scenario.rawValue)
                XCTAssertTrue(
                    scenario.recommender(useLiveModel: true) is ScenarioRecommender, scenario.rawValue)
            }
        }

        private func run(_ scenario: ResultScenario) async throws -> Recommendation {
            var stub = try XCTUnwrap(scenario.recommender(useLiveModel: false) as? ScenarioRecommender)
            stub.delay = .zero
            let result = try XCTUnwrap(scenario.result)
            let context = AdviceContextBuilder().context(
                for: result, estimate: PlaceholderSoilHealthEstimator().estimate(result), history: [])
            return try await stub.recommend(for: context)
        }

        func testBannedWordScenarioKeepsTheStepsButNotTheSummary() async throws {
            let recommendation = try await run(.modelWritesBannedWord)

            XCTAssertFalse(recommendation.summary.lowercased().contains("healthy"))
            XCTAssertEqual(recommendation.steps.map(\.actionID), [.resampleLater, .keepNotes])
            XCTAssertEqual(recommendation.steps.first?.why, "A second sample shows whether this holds.")
        }

        func testSeveralRulesScenarioIsRejectedAsAWhole() async {
            do {
                _ = try await run(.modelBreaksSeveralRules)
                XCTFail("Expected the answer to be rejected")
            } catch {
                XCTAssertEqual(
                    error as? AdviceFailure, .useStandardAdvice(note: AdviceFailure.failedChecksNote))
            }
        }

        func testBadIDScenarioIsFilledInWithApprovedReasons() async throws {
            let recommendation = try await run(.modelPicksBadIDs)

            XCTAssertEqual(recommendation.steps.map(\.actionID), [.resampleLater, .keepNotes])
            XCTAssertEqual(
                recommendation.steps.map(\.why), [AdviceReasons.sampleVaries, AdviceReasons.notes])
        }
    }
#endif
