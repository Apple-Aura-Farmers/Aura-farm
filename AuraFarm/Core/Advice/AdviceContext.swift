import Foundation

/// Everything the advice may say about one sample, already decided by code. The model only
/// phrases it.
///
/// Built from `docs/advice-content.md` (the team's "Advice content, Phase 1", approved
/// 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
struct AdviceContext: Equatable {
    struct OrganismReading: Equatable {
        var note: OrganismNote
        var count: Int
        /// Organisms per kept frame.
        var perFrame: Double
        var band: CountBands.Band
        /// False when the band is low but too few frames were looked at to read anything
        /// into it. The band stays low for the patterns; the prompt says "few seen".
        var lowIsMeaningful: Bool
    }

    /// An organism shown in the counts but not interpreted: the review pile, the trust
    /// check, and labels no note covers.
    struct AlsoSeen: Equatable {
        var displayName: String
        var count: Int
    }

    struct SuggestedAction: Equatable {
        var action: AdviceAction
        /// A short internal label naming what triggered it, for example "euglenoids dominant".
        /// For tests, logs and the inspector; not written for farmers.
        var because: String
        /// A plain sentence a helper can read aloud, saying why this action fits. The model
        /// builds on it, and it is shown when the model's own reason is missing or fails a check.
        var reason: String
    }

    var result: SoilResult
    var estimate: SoilHealthEstimate
    /// Most counted first.
    var interpreted: [OrganismReading]
    /// Most counted first.
    var alsoSeen: [AlsoSeen]
    /// In `AdvicePattern.allCases` order.
    var patterns: [AdvicePattern]
    /// After exclusions, in `AdviceAction.ID.allCases` order.
    var actions: [SuggestedAction]
    /// Newest first.
    var history: [PastResult]
    /// Plain sentences.
    var cautions: [String]

    /// Interpreted organisms per kept frame, worked out as `PastResult.organismsPerFrame` is.
    var interpretedPerFrame: Double {
        Double(interpreted.reduce(0) { $0 + $1.count }) / Double(max(result.framesKept, 1))
    }

    /// Kinds of interpreted organism counted, as `PastResult.interpretedKinds`.
    var interpretedKinds: Int { interpreted.count }
}
