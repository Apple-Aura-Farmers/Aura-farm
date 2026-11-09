import AuraFarmKit
import Foundation
import SwiftData

/// Fertilizer or organic matter the farmer put on a field, as reported to the helper.
@Model
final class FertilizerApplication {
    var appliedOn: Date
    /// An `AppliedProduct` raw value. Kept as text so a value a newer build adds still loads.
    var productRaw: String
    /// The brand or product, for a compound or other fertilizer. Empty otherwise.
    var productName: String = ""
    /// The amount for the whole field, in kilograms.
    var kilograms: Double
    var notes: String = ""
    var season: Season? = nil

    init(appliedOn: Date, product: AppliedProduct, kilograms: Double) {
        self.appliedOn = appliedOn
        self.productRaw = product.rawValue
        self.kilograms = kilograms
    }

    var product: AppliedProduct {
        get { AppliedProduct(rawValue: productRaw) ?? .other }
        set { productRaw = newValue.rawValue }
    }

    /// "Urea", or "NPK compound (e.g. Phonska) · Phonska 15-15-15"
    var label: String {
        let name = productName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? product.label : "\(product.label) · \(name)"
    }
}
