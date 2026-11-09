import Foundation

/// A pattern across the organisms in a sample. The builder decides which match; the model
/// is only told their meaning.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum AdvicePattern: String, CaseIterable {
    case severalRoles
    case euglenoidsDominant
    case cleanWaterAlgae
    case mixedSignals
    case predatorWithLowPrey
    case plentyOfVorticella
    case plentyOfTestateAmoebae
    case nematodesHigh
    case drainedLowCounts
    case onlyOneKind
    case nothingInterpretable
    case possibleMisidentification

    /// A warning: "keep doing what you're doing" is never offered beside it.
    var isConcern: Bool {
        switch self {
        case .euglenoidsDominant, .mixedSignals, .nematodesHigh, .possibleMisidentification,
            .nothingInterpretable, .onlyOneKind:
            return true
        default:
            return false
        }
    }

    /// The sample can't be trusted, so only sampling again and keeping notes are offered.
    var blocksImprovementActions: Bool {
        switch self {
        case .possibleMisidentification, .nothingInterpretable, .mixedSignals: return true
        default: return false
        }
    }

    /// A short name for the prompt.
    var title: String {
        switch self {
        case .severalRoles: return "Several roles present"
        case .euglenoidsDominant: return "Euglenoids dominant"
        case .cleanWaterAlgae: return "Clean-water algae present"
        case .mixedSignals: return "Mixed signals"
        case .predatorWithLowPrey: return "Predator with little prey"
        case .plentyOfVorticella: return "Plenty of Vorticella"
        case .plentyOfTestateAmoebae: return "Plenty of testate amoebae"
        case .nematodesHigh: return "Nematodes high"
        case .drainedLowCounts: return "Drained field"
        case .onlyOneKind: return "Only one kind"
        case .nothingInterpretable: return "Nothing that can be read"
        case .possibleMisidentification: return "Possible misidentification"
        }
    }

    /// What the model is told the pattern might mean.
    var meaning: String {
        switch self {
        case .severalRoles: return "A varied, layered food web. This is the most encouraging pattern."
        case .euglenoidsDominant: return "Still, nutrient-heavy water; possibly too much nitrogen."
        case .cleanWaterAlgae: return "Lower nutrients, cleaner water."
        case .mixedSignals: return "The signs point different ways. Do not draw a conclusion; sample again."
        case .predatorWithLowPrey:
            return "The predator may be eating them down, so low Paramecium is not a sign of poor soil here."
        case .plentyOfVorticella: return "Enough oxygen in the soil water."
        case .plentyOfTestateAmoebae: return "Moist soil rich in organic matter."
        case .nematodesHigh: return "Could be helpful worms or root pests. The app cannot tell which."
        case .drainedLowCounts: return "Low counts are expected in a drained field."
        case .onlyOneKind: return "Too narrow to judge; probably a sampling issue."
        case .nothingInterpretable: return "Nothing seen can be read yet; sample again."
        case .possibleMisidentification: return "The detector's labels may be off; sample again."
        }
    }
}
