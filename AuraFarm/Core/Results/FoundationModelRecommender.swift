import Foundation
import FoundationModels
import os

/// Writes a recommendation with Apple's on-device language model.
///
/// The model knows nothing about this soil beyond what the prompt tells it, and nothing it
/// says has been checked by an agronomist. `AdvicePromptBuilder` hands it only the approved
/// facts and actions that apply to this sample, so it phrases advice rather than inventing
/// it, and the screen labels what it writes as generated.
///
/// Every request starts from a clean session, so retries never pile up history in the model's
/// context window. `prewarm()` keeps one ready session for the next request; it is guarded by
/// a lock, so the class needs no actor.
final class FoundationModelRecommender: RecommendationProviding {
    let model: SystemLanguageModel

    /// A session made ahead of time by `prewarm()`, taken (and so cleared) by the next request.
    private let kept = OSAllocatedUnfairLock<LanguageModelSession?>(uncheckedState: nil)

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    var availability: RecommenderAvailability {
        switch model.availability {
        case .available:
            return model.supportsLocale()
                ? .available
                : .unavailable(reason: "Apple Intelligence doesn't support this phone's language yet.")
        case .unavailable(.deviceNotEligible):
            return .unavailable(reason: "This iPhone cannot run Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(reason: "Apple Intelligence is turned off in Settings.")
        case .unavailable(.modelNotReady):
            return .unavailable(reason: "Apple Intelligence is still downloading. Try again later.")
        case .unavailable:
            return .unavailable(reason: "Apple Intelligence is not available right now.")
        }
    }

    func prewarm() {
        let session = makeSession()
        session.prewarm()
        kept.withLockUnchecked { $0 = session }
    }

    func recommend(
        for context: AdviceContext, freshWording: Bool,
        onProgress: @escaping @Sendable (AdviceProgress) -> Void
    ) async throws -> Recommendation {
        let (_, outcome) = try await generate(
            for: context, freshWording: freshWording, onProgress: onProgress)
        if outcome.rejectWhole { throw AdviceFailure.useStandardAdvice(note: AdviceFailure.failedChecksNote) }
        return outcome.recommendation
    }

    /// Writes an answer and runs it through the app's checks. The screen and the Advice check both
    /// use this. It throws only for errors from the model (as `AdviceFailure`); an answer that
    /// fails the checks comes back with `outcome.rejectWhole` set instead.
    func generate(
        for context: AdviceContext, freshWording: Bool,
        onProgress: @escaping @Sendable (AdviceProgress) -> Void
    ) async throws -> (advice: ModelAdvice, outcome: AdviceResponseMapper.Outcome) {
        let session =
            kept.withLockUnchecked { slot -> LanguageModelSession? in
                defer { slot = nil }
                return slot
            } ?? makeSession()

        let answer: GeneratedAdvice
        do {
            answer = try await write(
                with: session, prompt: AdvicePromptBuilder.prompt(for: context), freshWording: freshWording,
                onProgress: onProgress)
        } catch let error as LanguageModelSession.GenerationError {
            let kind = Self.kind(of: error)
            #if DEBUG
                Self.logger.debug("GenerationError: \(String(describing: error), privacy: .public)")
                if kind.isLikelyBug {
                    Self.logger.debug(
                        "This points at a bug in the prompt or schema: \(String(describing: kind), privacy: .public)"
                    )
                }
            #endif
            throw kind.failure
        }
        let advice = ModelAdvice(
            noticed: answer.noticed,
            picks: answer.actions.map { ModelAdvice.Pick(id: $0.id, why: $0.why) },
            summary: answer.summary
        )
        let outcome = AdviceResponseMapper.map(advice, context: context)
        #if DEBUG
            Self.log(advice, outcome: outcome, freshWording: freshWording)
        #endif
        return (advice, outcome)
    }

    private func makeSession() -> LanguageModelSession {
        LanguageModelSession(model: model, instructions: AdvicePromptBuilder.instructions())
    }

    /// Streams the answer for progress only, and returns the final, complete one. Greedy
    /// sampling makes the first answer for a sample repeatable; fresh wording uses the default
    /// sampling so it can differ. No partial text leaves this method.
    private func write(
        with session: LanguageModelSession, prompt: String, freshWording: Bool,
        onProgress: @escaping @Sendable (AdviceProgress) -> Void
    ) async throws -> GeneratedAdvice {
        let options = freshWording ? GenerationOptions() : GenerationOptions(sampling: .greedy)
        let stream = session.streamResponse(to: prompt, generating: GeneratedAdvice.self, options: options)

        var latest: GeneratedContent?
        var reported: AdviceProgress?
        for try await snapshot in stream {
            latest = snapshot.rawContent
            let partial = snapshot.content
            let progress = AdviceProgress.from(
                noticedCount: partial.noticed?.count ?? 0, actionCount: partial.actions?.count ?? 0,
                hasSummary: partial.summary != nil)
            if progress != reported {
                reported = progress
                onProgress(progress)
            }
        }
        guard let latest else { throw ModelErrorKind.decodingFailure.failure }
        do {
            return try GeneratedAdvice(latest)
        } catch {
            // The stream ended before the answer was complete.
            throw ModelErrorKind.decodingFailure.failure
        }
    }

    /// Which kind of error the framework threw.
    static func kind(of error: LanguageModelSession.GenerationError) -> ModelErrorKind {
        switch error {
        case .guardrailViolation: return .guardrailViolation
        case .refusal: return .refusal
        case .unsupportedLanguageOrLocale: return .unsupportedLanguageOrLocale
        case .exceededContextWindowSize: return .exceededContextWindowSize
        case .decodingFailure: return .decodingFailure
        case .unsupportedGuide: return .unsupportedGuide
        case .rateLimited: return .rateLimited
        case .concurrentRequests: return .concurrentRequests
        case .assetsUnavailable: return .assetsUnavailable
        @unknown default: return .other
        }
    }

    #if DEBUG
        private static let logger = Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "AuraFarm", category: "advice")

        /// The model's raw answer, before mapping, for the Xcode console on a phone.
        private static func log(
            _ advice: ModelAdvice, outcome: AdviceResponseMapper.Outcome, freshWording: Bool
        ) {
            logger.debug("Fresh wording: \(freshWording, privacy: .public)")
            let picks = advice.picks.map { "\($0.id): \($0.why)" }.joined(separator: " | ")
            logger.debug("Model noticed: \(advice.noticed.joined(separator: " | "), privacy: .public)")
            logger.debug("Model picks: \(picks, privacy: .public)")
            logger.debug("Model summary: \(advice.summary, privacy: .public)")
            logger.debug("Dropped picks: \(outcome.droppedPicks, privacy: .public)")
            logger.debug("Failed checks: \(outcome.findings.count, privacy: .public)")
        }
    #endif
}
