import Foundation

/// Apple Intelligence advice kept with a sample, so reopening the sample shows the same
/// words. Standard advice is never saved.
struct SavedAdvice: Codable, Equatable {
    /// Always from the on-device model.
    var recommendation: Recommendation
    var writtenAt: Date
    /// `AdviceContentVersion.current` when it was written.
    var contentVersion: String
    var appVersion: String?

    /// True when the advice rules have changed since this was written.
    var isFromOlderRules: Bool { contentVersion != AdviceContentVersion.current }
}
