import AuraFarmKit
import Foundation
import SwiftData

/// One growing season on a field: what was planted and when, what was put on, and the harvest.
@Model
final class Season {
    /// What the team calls it, for example "Wet season 2026–27".
    var name: String
    /// The rice variety, for example "Inpari 32". Empty when not known.
    var variety: String = ""
    /// The transplanting date. The fertilizer plan's dates count from it.
    var plantedOn: Date? = nil
    /// nil while the crop is still in the field.
    var harvestedOn: Date? = nil
    /// Unhusked rice, tonnes a hectare. nil until the harvest is in.
    var yieldTonnesPerHectare: Double? = nil
    var notes: String = ""
    var createdAt: Date
    var field: Field? = nil

    @Relationship(deleteRule: .cascade, inverse: \FertilizerApplication.season)
    var applications: [FertilizerApplication] = []

    init(name: String, plantedOn: Date? = nil, createdAt: Date = .now) {
        self.name = name
        self.plantedOn = plantedOn
        self.createdAt = createdAt
    }

    /// When the season began, for ordering: the transplanting date, or when it was added.
    var startedAt: Date {
        plantedOn ?? createdAt
    }

    /// Applications, oldest first.
    var sortedApplications: [FertilizerApplication] {
        applications.sorted { $0.appliedOn < $1.appliedOn }
    }

    /// What has gone on, as the progress check reads it.
    var appliedAmounts: [(product: AppliedProduct, kilograms: Double)] {
        applications.map { (product: $0.product, kilograms: $0.kilograms) }
    }
}
