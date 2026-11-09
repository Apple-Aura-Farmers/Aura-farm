import AuraFarmKit
import Foundation

/// One row of the count breakdown.
struct TaxonCount: Identifiable, Equatable {
    /// The everyday name, for example "Hypotrich ciliates".
    var name: String
    /// The scientific or model label, for example "Hypotrichida". nil when there is none,
    /// as for the row that collects unmapped classes.
    var label: String?
    var count: Int

    var id: String { label ?? name }
}

/// The two ways the counts can be named while the team decides which one to keep.
///
/// The detector names five classes (euglena, paramecium, stentor, volvox, vorticella), but
/// `OrganismGroup` lists five other groups written for an earlier model. Both are shown, one
/// tab each, until that is settled.
enum OrganismTaxonomy: String, CaseIterable, Identifiable {
    /// The detector's own class labels.
    case modelClass
    /// `OrganismGroup`, reached through `ProvisionalTaxonMapping`.
    case organismGroup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .modelClass: return "Model classes"
        case .organismGroup: return "Organism groups"
        }
    }

    /// The name used for classes no organism group takes.
    static let unmappedName = "Not in any group"

    /// The counts in this taxonomy, most counted first, and groups found zero times left out.
    func rows(
        from counts: [String: Int],
        mapping: ProvisionalTaxonMapping = ProvisionalTaxonMapping()
    ) -> [TaxonCount] {
        let rows: [TaxonCount]
        switch self {
        case .modelClass:
            rows = counts.map { label, count in
                TaxonCount(name: label.capitalized, label: label, count: count)
            }
        case .organismGroup:
            var byGroup: [OrganismGroup: Int] = [:]
            var unmapped = 0
            for (label, count) in counts {
                if let group = mapping.group(forClass: label) {
                    byGroup[group, default: 0] += count
                } else {
                    unmapped += count
                }
            }
            rows =
                byGroup.map { group, count in
                    TaxonCount(name: group.commonName, label: group.rawValue, count: count)
                } + [TaxonCount(name: Self.unmappedName, label: nil, count: unmapped)]
        }
        return
            rows
            .filter { $0.count > 0 }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.name < $1.name }
    }
}

/// Which `OrganismGroup` each detector class is counted under on the organism groups tab.
///
/// PROVISIONAL: not checked by anyone who knows the organisms. Paramecium, Stentor and
/// Vorticella are all ciliates, and Hypotrichida is the only ciliate group in the list, so
/// they go there as the nearest fit rather than a correct one. Euglena and Volvox fit none
/// of the groups and are collected as unmapped. Change the table, not the screen, once the
/// team has decided.
struct ProvisionalTaxonMapping {
    var table: [String: OrganismGroup] = [
        "paramecium": .hypotrichida,
        "stentor": .hypotrichida,
        "vorticella": .hypotrichida,
    ]

    /// The group for a detector class. A class the model calls by a group's own name, as an
    /// older model did, is that group.
    func group(forClass label: String) -> OrganismGroup? {
        table[label.lowercased()] ?? OrganismGroup(rawValue: label)
    }
}
