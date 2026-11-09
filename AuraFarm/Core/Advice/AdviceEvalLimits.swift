import Foundation

/// Limits for grading a model answer in the Advice check.
///
/// PLACEHOLDERS: not calibrated or measured on a device.
enum AdviceEvalLimits {
    /// An answer that takes longer than this many seconds is graded as slow.
    static let slowSeconds = 15.0
    /// The summary length the instructions ask for, in words. The checker allows more.
    static let summaryWords = 25
    /// How many words of an action's wording, counted from the start, a reason may not repeat.
    static let repeatedWordingWords = 6
}
