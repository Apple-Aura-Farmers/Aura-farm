import Foundation

/// Why the model's advice could not be shown, and what the screen does about it.
enum AdviceFailure: Error, Equatable {
    /// Trying again will not help, so the screen shows standard advice with this note.
    case useStandardAdvice(note: String)
    /// The model may work in a moment; the screen offers Try again with this message.
    case retry(message: String)
}

/// The messages, in one place so the recommender, the screen's test scenarios and the tests
/// agree.
extension AdviceFailure {
    static let failedChecksNote =
        "The written advice didn't pass the app's checks, so standard advice is shown."
    static let refusedNote =
        "Apple Intelligence couldn't write advice for this sample, so standard advice is shown."
    static let languageNote =
        "Apple Intelligence doesn't support this phone's language yet, so standard advice is shown."
    static let unfinishedNote = "Apple Intelligence couldn't finish this advice, so standard advice is shown."
    static let busyMessage = "Apple Intelligence is busy. Try again in a moment."
    static let gettingReadyMessage = "Apple Intelligence is still getting ready. Try again in a moment."
    static let genericMessage = "The advice could not be written. Try again."
    static let timeoutMessage = "Apple Intelligence is taking too long. Try again."
}
