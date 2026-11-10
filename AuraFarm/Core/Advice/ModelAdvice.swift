import Foundation

/// The on-device model's answer, copied out of the generated type so the advice logic never
/// depends on FoundationModels.
///
/// Part of the advice built from `docs/advice-content.md` (the team's "Advice content,
/// Phase 1", approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
struct ModelAdvice: Equatable {
    /// One action the model picked, by id, with its reason.
    struct Pick: Equatable {
        var id: String
        var why: String
    }

    var noticed: [String]
    var picks: [Pick]
    var summary: String
}
