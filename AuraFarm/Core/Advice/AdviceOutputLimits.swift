import Foundation

/// How long the model's own words may be, and how many parts may fail before the whole
/// answer is thrown out.
///
/// PLACEHOLDERS: not calibrated. Each word limit is looser than the instructions, so normal
/// answers pass.
struct AdviceOutputLimits: Equatable {
    var summaryWords = 35
    var whyWords = 25
    var noticedWords = 30
    /// More failing parts than this and standard advice is shown instead.
    var maxFailedFields = 1
}
