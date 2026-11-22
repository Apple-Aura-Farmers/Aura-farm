import Foundation

/// The three kinds of soil life the results screen counts, and the rest.
///
/// PROVISIONAL, like `ProvisionalTaxonMapping`: the table below is a biologist's-eye guess at
/// where each detector class sits (amoebae and ciliates are protists, as the design says) and has
/// not been checked by anyone who knows the organisms. Change the table, not the screen.
enum SoilLifeGroup: CaseIterable, Identifiable {
    case protists, nematodes, rotifers, other

    var id: Self { self }

    var title: String {
        switch self {
        case .protists: "Protists"
        case .nematodes: "Nematodes"
        case .rotifers: "Rotifers"
        case .other: "Other"
        }
    }

    /// The image in the asset catalogue; nil for Other, which has none.
    var imageName: String? {
        switch self {
        case .protists: "Protists"
        case .nematodes: "Nematodes"
        case .rotifers: "Rotifiers"
        case .other: nil
        }
    }

    /// One organism of a type, as the detector named it.
    struct Organism: Identifiable, Equatable {
        var name: String
        var description: String
        var count: Int
        var id: String { name }
    }

    /// A kind within a group, for example Ciliates within Protists.
    struct Kind: Identifiable, Equatable {
        var name: String
        var count: Int
        var organisms: [Organism]
        var id: String { name }
    }

    /// Detector label (lowercased) to its group and kind. A label missing here is Other.
    private static let table: [String: (SoilLifeGroup, String)] = {
        var t: [String: (SoilLifeGroup, String)] = [:]
        for l in ["amoeba", "arcellinida"] { t[l] = (.protists, "Amoebae") }
        for l in [
            "hypotrichida", "paramecium", "paramecium_coleps", "stentor", "vorticella", "frontonia",
            "coleps",
        ] { t[l] = (.protists, "Ciliates") }
        for l in ["euglena", "euglenoid", "phacus", "lepocinclis"] { t[l] = (.protists, "Euglenoids") }
        for l in [
            "volvox", "dinobryon", "micrasterias", "closterium", "cylindrocystis", "pinnularia",
            "pleurotaenium", "ceratium", "peridinium",
        ] { t[l] = (.protists, "Algae") }
        for l in ["didinium_phacus_collodictyon", "collodictyon", "didinium"] {
            t[l] = (.protists, "Other protists")
        }
        for l in ["nematode", "nematoda"] { t[l] = (.nematodes, "Nematodes") }
        t["digononta"] = (.rotifers, "Bdelloid rotifers")
        t["monogononta"] = (.rotifers, "Monogonont rotifers")
        return t
    }()

    /// The counts sorted into groups and kinds, most counted first. Zero counts are left out.
    static func summarize(_ counts: [String: Int]) -> [SoilLifeGroup: [Kind]] {
        var sorted: [SoilLifeGroup: [String: [Organism]]] = [:]
        for (label, count) in counts where count > 0 {
            let (group, kind) = table[label.lowercased()] ?? (.other, "Not sorted yet")
            let note = OrganismNotes.note(forLabel: label)
            let organism = Organism(
                name: note?.displayName ?? OrganismDisplayName.label(label),
                description: note?.plainDescription ?? "", count: count)
            sorted[group, default: [:]][kind, default: []].append(organism)
        }
        return sorted.mapValues { kinds in
            kinds.map { name, organisms in
                Kind(
                    name: name, count: organisms.map(\.count).reduce(0, +),
                    organisms: organisms.sorted { $0.count > $1.count })
            }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
        }
    }
}
