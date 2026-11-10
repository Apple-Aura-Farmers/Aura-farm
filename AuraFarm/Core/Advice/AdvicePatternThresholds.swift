import Foundation

/// Limits for the patterns and action rules.
///
/// The rules mirror `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change them in both places.
///
/// PLACEHOLDERS: none of these are calibrated. Shares are fractions of a total count, from
/// 0 to 1. Replace them once the team's test sweeps show what is typical.
struct AdvicePatternThresholds {
    /// Euglenoids at least this share of the interpreted total are dominant...
    var euglenoidsDominantShare: Double = 0.5
    /// ...as long as ciliates are below this share of it.
    var fewCiliatesShare: Double = 0.2
    /// Clean-water algae only read as clean water while euglenoids are below this share.
    var cleanWaterEuglenoidShare: Double = 0.2
    /// Trust-check organisms at least this share of everything counted mean the labels may
    /// be off.
    var misidentificationShare: Double = 0.2
    /// Interpreted organisms per kept frame below this is low abundance.
    var lowAbundancePerFrame: Double = 1.0
    /// This many interpreted kinds or fewer is low diversity.
    var lowDiversityKinds: Int = 2
    /// Fewer kept frames than this is too short a sweep to lean on.
    var fewFrames: Int = 5
    /// PLACEHOLDER, not calibrated: a low count only means something once at least this
    /// many frames of the slide were looked at.
    var minimumFramesForLow: Int = 20
    /// PLACEHOLDER, not calibrated: fewer organisms than this never count as high, however
    /// few frames there were.
    var minimumCountForHigh: Int = 3
}
