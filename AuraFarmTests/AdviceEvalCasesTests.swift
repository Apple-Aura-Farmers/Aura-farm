import XCTest

@testable import AuraFarm

final class AdviceEvalCasesTests: XCTestCase {
    /// Expectations that don't hold with today's rules, keyed "case-id|check". They are wrapped in
    /// `XCTExpectFailure`, so the build stays green while the team decides whether the rule or the
    /// expectation is wrong. Neither has been changed to make a case pass.
    private let knownFailures: [String: String] = [
        "poor-twice|offer":
            "the builder suggests lab_test (poor twice in a row), but trimming to six keeps talk_extension "
            + "and drops it, because lab_test is low in fallbackPriority"
    ]

    private func context(for evalCase: AdviceEvalCase) -> AdviceContext {
        AdviceContextBuilder().context(
            for: evalCase.result,
            estimate: PlaceholderSoilHealthEstimator().estimate(evalCase.result),
            history: evalCase.history)
    }

    /// Asserts a check, expecting it to fail when it is a known failure.
    private func assertCheck(_ id: String, _ check: String, problem: String?) {
        let key = "\(id)|\(check)"
        if let why = knownFailures[key] {
            XCTExpectFailure("\(id): \(why)") {
                XCTAssertNil(problem, "\(id) [\(check)]")
            }
        } else {
            XCTAssertNil(problem, "\(id) [\(check)]")
        }
    }

    func testThereAreAtLeastTwentyOneCasesWithUniqueIDs() {
        let ids = AdviceEvalCases.all.map(\.id)

        XCTAssertGreaterThanOrEqual(ids.count, 21)
        XCTAssertEqual(Set(ids).count, ids.count)
        for id in ids {
            XCTAssertNotNil(id.range(of: #"^[a-z0-9]+(-[a-z0-9]+)*$"#, options: .regularExpression), id)
        }
    }

    func testCasesHaveNoSweepAndTheDefaultsTheyDeclare() {
        for evalCase in AdviceEvalCases.all {
            XCTAssertNil(evalCase.result.sweep, evalCase.id)
            XCTAssertEqual(evalCase.result.sampleID, evalCase.id)
            XCTAssertEqual(evalCase.result.recordedAt, Date(timeIntervalSince1970: 1_793_000_000))
        }
    }

    func testEveryCaseMeetsItsExpectations() {
        for evalCase in AdviceEvalCases.all {
            let context = context(for: evalCase)
            let patterns = Set(context.patterns)
            let offered = Set(AdvicePromptBuilder.offeredActions(for: context).map(\.action.id))
            let id = evalCase.id

            assertCheck(
                id, "level",
                problem: context.estimate.level == evalCase.expectedLevel
                    ? nil : "level is \(context.estimate.level), expected \(evalCase.expectedLevel)")
            assertCheck(
                id, "match",
                problem: evalCase.mustMatch.isSubset(of: patterns)
                    ? nil
                    : "missing patterns \(evalCase.mustMatch.subtracting(patterns).map(\.rawValue).sorted())")
            assertCheck(
                id, "notMatch",
                problem: evalCase.mustNotMatch.isDisjoint(with: patterns)
                    ? nil
                    : "unwanted patterns \(evalCase.mustNotMatch.intersection(patterns).map(\.rawValue).sorted())"
            )
            assertCheck(
                id, "offer",
                problem: evalCase.mustOffer.isSubset(of: offered)
                    ? nil : "not offered \(evalCase.mustOffer.subtracting(offered).map(\.rawValue).sorted())")
            assertCheck(
                id, "notOffer",
                problem: evalCase.mustNotOffer.isDisjoint(with: offered)
                    ? nil
                    : "unwanted offers \(evalCase.mustNotOffer.intersection(offered).map(\.rawValue).sorted())"
            )
        }
    }

    func testTheBundledLabelsKeepStentorAndVolvoxOutOfTheAdvice() throws {
        let evalCase = try XCTUnwrap(AdviceEvalCases.all.first { $0.id == "bundled-labels-good" })
        let context = context(for: evalCase)

        XCTAssertEqual(Set(context.alsoSeen.map(\.displayName)), ["Stentor", "Volvox"])
    }

    func testModelAskedFollowsTheExpectedLevel() {
        for evalCase in AdviceEvalCases.all {
            let asked = [SoilHealthEstimate.Level.good, .fair, .poor].contains(evalCase.expectedLevel)
            XCTAssertEqual(evalCase.modelAsked, asked, evalCase.id)
        }
    }
}
