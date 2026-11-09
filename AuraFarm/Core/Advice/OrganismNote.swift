import Foundation

/// What one detector class might say about the soil, for the advice to explain.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist. Rows marked `.must` need expert review.
struct OrganismNote: Equatable {
    /// Whether the advice reads anything into this organism.
    enum Use: Equatable {
        /// Counts toward the advice.
        case interpreted
        /// Shown in the counts but not interpreted, until the team has looked at it.
        case reviewPile
        /// Not interpreted. A large share of it means the labels may be off.
        case trustCheck
    }

    /// What it does in the food web.
    enum Role: Equatable {
        case bacteriaFeeder
        case predator
        /// Makes its own food from light.
        case alga
        /// Light plus dissolved food, as the euglenoids do.
        case lightAndDissolved
        case mixed
    }

    /// How common it usually is, which picks its count bands.
    enum Abundance: Equatable {
        case common
        case moderate
        case scarce
    }

    enum Confidence: Equatable {
        case low
        case medium
    }

    /// How much expert review the row needs before it is trusted.
    enum ReviewNeed: Equatable {
        case must
        case should
        case light
    }

    /// The model label, lowercased, for example "paramecium".
    var label: String
    /// For example "Paramecium" or "Testate amoebae".
    var displayName: String
    var use: Use
    /// nil for the review pile and the trust check.
    var role: Role?
    /// nil for the review pile and the trust check.
    var abundance: Abundance?
    var plainDescription: String
    /// What a high count might suggest. nil for the review pile and the trust check.
    var highSuggests: String?
    var lowSuggests: String?
    var confidence: Confidence
    var review: ReviewNeed
    /// Why it is not interpreted. Only for the review pile and the trust check.
    var pileReason: String?
}
