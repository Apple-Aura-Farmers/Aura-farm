import Foundation

/// Where a count sits for its kind of organism, so the advice can say "a lot" or "a little".
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
///
/// PLACEHOLDERS: the limits are guesses, in organisms per kept frame, until the team's own
/// test sweeps of typical fields replace them. Counts per frame depend on how much the slide
/// was diluted, which is not standardised yet.
struct CountBands {
    enum Band: Equatable {
        case low
        case typical
        case high
    }

    struct Limits {
        /// Below this is low. nil when the organism is scarce enough that few is normal.
        var lowBelow: Double?
        /// Above this is high.
        var highAbove: Double
    }

    var common = Limits(lowBelow: 0.3, highAbove: 2)
    var moderate = Limits(lowBelow: 0.1, highAbove: 1)
    var scarce = Limits(lowBelow: nil, highAbove: 0.3)

    func band(perFrame: Double, abundance: OrganismNote.Abundance) -> Band {
        let limits: Limits
        switch abundance {
        case .common: limits = common
        case .moderate: limits = moderate
        case .scarce: limits = scarce
        }
        if perFrame > limits.highAbove { return .high }
        if let lowBelow = limits.lowBelow, perFrame < lowBelow { return .low }
        return .typical
    }
}
