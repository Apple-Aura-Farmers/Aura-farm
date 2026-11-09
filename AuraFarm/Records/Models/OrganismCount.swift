import AuraFarmKit
import Foundation
import SwiftData

/// How many of one organism group a soil test counted.
@Model
final class OrganismCount {
    /// The detector's class label, for example `Nematoda`.
    var taxon: String
    var count: Int
    var soilTest: SoilTest? = nil

    init(taxon: String, count: Int) {
        self.taxon = taxon
        self.count = count
    }

    /// The everyday name, for example "Nematodes".
    var commonName: String {
        OrganismGroup.commonName(forTaxon: taxon)
    }
}
