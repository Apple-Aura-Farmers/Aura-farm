import Foundation

/// The three nutrients a paddy soil test reads, the way the field kit and a lab report name them.
public enum Nutrient: String, CaseIterable, Codable, Sendable {
    case nitrogen
    case phosphorus
    case potassium

    /// "Nitrogen"
    public var name: String {
        switch self {
        case .nitrogen: return "Nitrogen"
        case .phosphorus: return "Phosphorus"
        case .potassium: return "Potassium"
        }
    }

    /// "N", "P" or "K", as on the kit's colour chart.
    public var symbol: String {
        switch self {
        case .nitrogen: return "N"
        case .phosphorus: return "P"
        case .potassium: return "K"
        }
    }
}

/// The class a soil test puts a nutrient in. The paddy soil test kit (PUTS) reads one of these
/// straight off its colour chart; a lab value is turned into one with `NutrientThresholds`.
public enum NutrientLevel: String, CaseIterable, Codable, Comparable, Sendable {
    case low
    case medium
    case high

    /// "Low", "Medium" or "High"
    public var label: String {
        switch self {
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }

    /// 1, 2 or 3, for charting a level over time.
    public var rank: Int {
        switch self {
        case .low: return 1
        case .medium: return 2
        case .high: return 3
        }
    }

    public static func < (lhs: NutrientLevel, rhs: NutrientLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Where a set of NPK results came from. It sets how far the plan built on them can be trusted.
public enum NutrientSource: String, CaseIterable, Codable, Sendable {
    /// The paddy soil test kit (Perangkat Uji Tanah Sawah, PUTS) or a similar colour-chart kit.
    case soilTestKit
    /// A soil laboratory report.
    case laboratory

    public var label: String {
        switch self {
        case .soilTestKit: return "Soil test kit"
        case .laboratory: return "Soil lab"
        }
    }
}

/// What happened to the rice straw after the last harvest. Straw put back into the paddy returns
/// most of the potassium the crop took up, so it lowers the potash dose.
public enum StrawPractice: String, CaseIterable, Codable, Sendable {
    case unknown
    case returned
    case removed

    public var label: String {
        switch self {
        case .unknown: return "Not known"
        case .returned: return "Put back into the field"
        case .removed: return "Taken away or burned"
        }
    }
}
