import Foundation

/// Which trained detector to open.
///
/// V3 is the only one the app ships. V1, the five-class model the capture screen used, and V2,
/// the 23-class one the lab counted with, were taken out when V3 replaced both. Run records and
/// `soil_results` rows written before that still name them, so `DetectorModel(rawValue:)` returns
/// nil for "v1" and "v2" and every reader of a stored name falls back rather than assuming.
enum DetectorModel: String, CaseIterable, Identifiable {
    case v3

    var id: String { rawValue }

    /// The compiled model's name in the bundle.
    var resourceName: String {
        switch self {
        case .v3: "SoilDetectorV3"
        }
    }

    /// The name of the output that holds the class scores.
    var scoresOutput: String {
        switch self {
        case .v3: "scores"
        }
    }

    /// Whether the scores are probabilities already. V3's graph ends in a sigmoid, so applying
    /// another would put every query at 0.5 or more.
    var scoresAreProbabilities: Bool {
        switch self {
        case .v3: true
        }
    }

    var displayName: String {
        switch self {
        case .v3: "V3 (22 classes)"
        }
    }

    /// The class list to fall back on when the model carries none of its own, slot 0 the
    /// background.
    var builtInClassNames: [String] {
        switch self {
        case .v3: Self.v3ClassNames
        }
    }

    /// V3's classes as exported, slot 0 the background. The model carries the same list in its
    /// metadata; this is the fallback when that is missing or the wrong length.
    static let v3ClassNames = [
        "background", "Amoeba", "Arcellinida", "Ceratium", "Closterium", "Cylindrocystis",
        "Didinium_Phacus_Collodictyon", "Digononta", "Dinobryon", "Euglena", "Frontonia",
        "Hypotrichida", "Lepocinclis", "Micrasterias", "Monogononta", "Nematode",
        "Paramecium_Coleps", "Peridinium", "Pinnularia", "Pleurotaenium", "Pyrocystis", "Volvox",
        "Vorticella",
    ]
}

/// How a raw label is shown on screen. Raw labels stay the data everywhere (tally, map, CSV, run
/// record); only what the helper reads goes through this.
enum OrganismDisplayName {
    /// "Didinium_Phacus_Collodictyon" is "Didinium / Phacus / Collodictyon"; other labels are
    /// unchanged.
    static func label(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " / ")
    }
}
