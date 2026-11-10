import Foundation

/// The kinds of error the on-device model can fail with, without the framework's own type, so
/// how each is handled can be tested without constructing one.
enum ModelErrorKind: Equatable, CaseIterable {
    case guardrailViolation
    case refusal
    case unsupportedLanguageOrLocale
    case exceededContextWindowSize
    case decodingFailure
    case unsupportedGuide
    case rateLimited
    case concurrentRequests
    case assetsUnavailable
    /// Any error not listed above.
    case other

    /// What the screen does about it.
    var failure: AdviceFailure {
        switch self {
        case .guardrailViolation, .refusal:
            return .useStandardAdvice(note: AdviceFailure.refusedNote)
        case .unsupportedLanguageOrLocale:
            return .useStandardAdvice(note: AdviceFailure.languageNote)
        case .exceededContextWindowSize, .decodingFailure, .unsupportedGuide:
            return .useStandardAdvice(note: AdviceFailure.unfinishedNote)
        case .rateLimited, .concurrentRequests:
            return .retry(message: AdviceFailure.busyMessage)
        case .assetsUnavailable:
            return .retry(message: AdviceFailure.gettingReadyMessage)
        case .other:
            return .retry(message: AdviceFailure.genericMessage)
        }
    }

    /// These mean a bug in the prompt or the schema rather than a bad moment.
    var isLikelyBug: Bool {
        switch self {
        case .exceededContextWindowSize, .decodingFailure, .unsupportedGuide: return true
        default: return false
        }
    }
}
