import Foundation

/// What to do about one field, worked out from its latest NPK results and microscope counts.
///
/// It never rates the soil on its own. Every piece of advice carries the actions behind it, how
/// far it can be trusted, and when to test again.
public struct SoilAdvice: Equatable, Sendable {
    /// Fertilizer to put on, one entry per nutrient that was tested. Empty without NPK results.
    public var doses: [FertilizerDose]
    /// Other things to do, most important first.
    public var actions: [AdviceAction]
    public var confidence: AdviceConfidence
    /// When to test again, and when a lab test is needed.
    public var retests: [String]
    /// What the advice rests on, in words a field helper can repeat to a farmer.
    public var basis: [String]

    public init(
        doses: [FertilizerDose],
        actions: [AdviceAction],
        confidence: AdviceConfidence,
        retests: [String],
        basis: [String]
    ) {
        self.doses = doses
        self.actions = actions
        self.confidence = confidence
        self.retests = retests
        self.basis = basis
    }
}

/// One fertilizer and how much of it to put on.
public struct FertilizerDose: Equatable, Sendable {
    public var fertilizer: Fertilizer
    /// The soil class the dose was chosen for.
    public var level: NutrientLevel
    public var kilogramsPerHectare: Double
    /// The dose for the whole field, when its area is known.
    public var kilogramsForField: Double?
    /// When to put it on.
    public var schedule: String

    public init(
        fertilizer: Fertilizer,
        level: NutrientLevel,
        kilogramsPerHectare: Double,
        kilogramsForField: Double?,
        schedule: String
    ) {
        self.fertilizer = fertilizer
        self.level = level
        self.kilogramsPerHectare = kilogramsPerHectare
        self.kilogramsForField = kilogramsForField
        self.schedule = schedule
    }
}

/// Something to do that is not a fertilizer dose: fix the pH, test again, check the slide.
public struct AdviceAction: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// About the soil itself, such as its pH.
        case soil
        /// About the microscope counts.
        case organisms
        /// A test that is missing or needs repeating.
        case testing
    }

    public var kind: Kind
    /// What to do, short enough to say out loud.
    public var title: String
    /// Why, and how.
    public var detail: String

    public init(kind: Kind, title: String, detail: String) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

/// How far the advice can be trusted, and why. There is deliberately no "certain": none of the
/// rules behind it has been checked on these farms.
public struct AdviceConfidence: Equatable, Sendable {
    public enum Level: Int, Comparable, Sendable {
        case low
        case fair
        case good

        public var label: String {
            switch self {
            case .low: return "Low"
            case .fair: return "Fair"
            case .good: return "Good"
            }
        }

        public static func < (lhs: Level, rhs: Level) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        /// One step down, stopping at low.
        var lowered: Level {
            Level(rawValue: rawValue - 1) ?? .low
        }
    }

    public var level: Level
    /// The reasons, plain sentences.
    public var reasons: [String]

    public init(level: Level, reasons: [String]) {
        self.level = level
        self.reasons = reasons
    }
}
