import Foundation

/// Which trained detector to open.
///
/// V1 is the five-class model the capture screen, the uploader and the results screen use. V2 is
/// the 23-class one, for live counting only. Their outputs differ: V1's scores are logits that
/// need a sigmoid; V2's graph ends in a sigmoid already, so its scores are probabilities.
enum DetectorModel: String, CaseIterable, Identifiable {
    case v1, v2

    var id: String { rawValue }

    /// The compiled model's name in the bundle.
    var resourceName: String {
        switch self {
        case .v1: "SoilDetector"
        case .v2: "SoilDetectorV2"
        }
    }

    /// The name of the output that holds the class scores.
    var scoresOutput: String {
        switch self {
        case .v1: "logits"
        case .v2: "scores"
        }
    }

    /// Whether the scores are probabilities already. Applying a sigmoid to V2's would put every
    /// query at 0.5 or more.
    var scoresAreProbabilities: Bool { self == .v2 }

    var displayName: String {
        switch self {
        case .v1: "V1 (5 classes)"
        case .v2: "V2 (23 classes)"
        }
    }

    /// V2's classes as exported, slot 0 the background. The model carries the same list in its
    /// metadata; this is the fallback when that is missing or the wrong length.
    static let v2ClassNames = [
        "background", "Amoeba", "Arcellinida", "Ceratium", "Closterium", "Cylindrocystis",
        "Didinium_Phacus_Collodictyon", "Digononta", "Dinobryon", "Euglena", "Frontonia",
        "Hypotrichida", "Lepocinclis", "Micrasterias", "Monogononta", "Nematode",
        "Paramecium_Coleps", "Peridinium", "Pinnularia", "Pleurotaenium", "Pyrocystis", "Stentor",
        "Volvox", "Vorticella",
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
