import Foundation

/// How acid or alkaline a paddy soil is, from its pH in water.
///
/// The bands follow the Balai Penelitian Tanah lab criteria: very acidic below 4.5, acidic to
/// 5.5, slightly acidic to 6.5, neutral to 7.5, alkaline above. Not calibrated by this team, and
/// the field kit's own colour chart may draw the lines a little differently.
public enum SoilAcidity: String, CaseIterable, Sendable {
    case veryAcidic
    case acidic
    case slightlyAcidic
    case neutral
    case alkaline

    /// Upper pH of each band, lowest band first. The last band has no upper bound.
    static let upperBounds: [(SoilAcidity, Double)] = [
        (.veryAcidic, 4.5),
        (.acidic, 5.5),
        (.slightlyAcidic, 6.5),
        (.neutral, 7.5),
    ]

    /// The pH values a soil can plausibly read. A value outside is a typing mistake.
    public static let plausibleRange: ClosedRange<Double> = 2.5...10.5

    public init(pH: Double) {
        for (band, upper) in Self.upperBounds where pH < upper {
            self = band
            return
        }
        self = .alkaline
    }

    public var label: String {
        switch self {
        case .veryAcidic: return "Very acidic"
        case .acidic: return "Acidic"
        case .slightlyAcidic: return "Slightly acidic"
        case .neutral: return "Neutral"
        case .alkaline: return "Alkaline"
        }
    }

    /// True when the pH is far enough off that the fix depends on a lab measurement.
    public var needsLabTest: Bool {
        switch self {
        case .veryAcidic, .acidic, .alkaline: return true
        case .slightlyAcidic, .neutral: return false
        }
    }
}
