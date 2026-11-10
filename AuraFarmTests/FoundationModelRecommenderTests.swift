import FoundationModels
import XCTest

@testable import AuraFarm

final class FoundationModelRecommenderTests: XCTestCase {
    func testEveryErrorKindMapsToItsFailure() {
        let expected: [ModelErrorKind: AdviceFailure] = [
            .guardrailViolation: .useStandardAdvice(
                note: "Apple Intelligence couldn't write advice for this sample, so standard advice is shown."
            ),
            .refusal: .useStandardAdvice(
                note: "Apple Intelligence couldn't write advice for this sample, so standard advice is shown."
            ),
            .unsupportedLanguageOrLocale: .useStandardAdvice(
                note:
                    "Apple Intelligence doesn't support this phone's language yet, so standard advice is shown."
            ),
            .exceededContextWindowSize: .useStandardAdvice(
                note: "Apple Intelligence couldn't finish this advice, so standard advice is shown."),
            .decodingFailure: .useStandardAdvice(
                note: "Apple Intelligence couldn't finish this advice, so standard advice is shown."),
            .unsupportedGuide: .useStandardAdvice(
                note: "Apple Intelligence couldn't finish this advice, so standard advice is shown."),
            .rateLimited: .retry(message: "Apple Intelligence is busy. Try again in a moment."),
            .concurrentRequests: .retry(message: "Apple Intelligence is busy. Try again in a moment."),
            .assetsUnavailable: .retry(
                message: "Apple Intelligence is still getting ready. Try again in a moment."),
            .other: .retry(message: "The advice could not be written. Try again."),
        ]

        XCTAssertEqual(Set(expected.keys), Set(ModelErrorKind.allCases))
        for (kind, failure) in expected {
            XCTAssertEqual(kind.failure, failure, "\(kind)")
        }
    }

    func testOnlyPromptOrSchemaProblemsAreLikelyBugs() {
        XCTAssertEqual(
            ModelErrorKind.allCases.filter(\.isLikelyBug),
            [.exceededContextWindowSize, .decodingFailure, .unsupportedGuide])
    }

    func testRealGenerationErrorsMapToTheirKind() {
        typealias GenerationError = LanguageModelSession.GenerationError
        let context = GenerationError.Context(debugDescription: "test")
        let cases: [(GenerationError, ModelErrorKind)] = [
            (.guardrailViolation(context), .guardrailViolation),
            (.refusal(.init(transcriptEntries: []), context), .refusal),
            (.unsupportedLanguageOrLocale(context), .unsupportedLanguageOrLocale),
            (.exceededContextWindowSize(context), .exceededContextWindowSize),
            (.decodingFailure(context), .decodingFailure),
            (.unsupportedGuide(context), .unsupportedGuide),
            (.rateLimited(context), .rateLimited),
            (.concurrentRequests(context), .concurrentRequests),
            (.assetsUnavailable(context), .assetsUnavailable),
        ]

        for (error, kind) in cases {
            XCTAssertEqual(FoundationModelRecommender.kind(of: error), kind, "\(error)")
        }
    }
}
