import AuraFarmKit
import Foundation
import SwiftData

/// One field, or paddy, of a farm. Soil tests are filed under a field so its soil life can be
/// followed from visit to visit.
@Model
final class Field {
    var name: String
    var crop: String
    /// Planted area in hectares. nil until someone enters it.
    var areaHectares: Double? = nil
    var createdAt: Date
    var farm: Farm? = nil
    /// The field's outline as drawn on the satellite map, as `FieldBoundary` JSON. nil until
    /// someone draws it.
    var boundaryData: Data? = nil

    /// Deleting a field keeps its soil tests: they go back to the inbox to be filed again.
    @Relationship(deleteRule: .nullify, inverse: \SoilTest.field)
    var soilTests: [SoilTest] = []

    /// NPK results typed in for this field. They belong to it alone, so deleting the field
    /// deletes them.
    @Relationship(deleteRule: .cascade, inverse: \NutrientTest.field)
    var nutrientTests: [NutrientTest] = []

    /// Growing seasons, with what was planted, put on and harvested. Deleted with the field.
    @Relationship(deleteRule: .cascade, inverse: \Season.field)
    var seasons: [Season] = []

    init(name: String, crop: String = "Rice", areaHectares: Double? = nil, createdAt: Date = .now) {
        self.name = name
        self.crop = crop
        self.areaHectares = areaHectares
        self.createdAt = createdAt
    }

    /// The most recent soil test filed here, if any.
    var latestSoilTest: SoilTest? {
        soilTests.max { $0.recordedAt < $1.recordedAt }
    }

    /// The outline drawn on the map. Setting nil, or an outline with fewer than three corners,
    /// removes it.
    var boundary: FieldBoundary? {
        get { boundaryData.flatMap(FieldBoundary.init(data:)) }
        set {
            guard let newValue, newValue.isComplete else {
                boundaryData = nil
                return
            }
            boundaryData = try? newValue.encoded()
        }
    }

    /// The most recent NPK results, if any.
    var latestNutrientTest: NutrientTest? {
        nutrientTests.max { $0.testedAt < $1.testedAt }
    }

    /// NPK results, newest first.
    var sortedNutrientTests: [NutrientTest] {
        nutrientTests.sorted { $0.testedAt > $1.testedAt }
    }

    /// Seasons, newest first.
    var sortedSeasons: [Season] {
        seasons.sorted { $0.startedAt > $1.startedAt }
    }

    /// The newest season not harvested yet: the one the plan's dates and progress are for.
    var currentSeason: Season? {
        sortedSeasons.first { $0.harvestedOn == nil }
    }

    /// Soil tests, newest first.
    var sortedSoilTests: [SoilTest] {
        soilTests.sorted { $0.recordedAt > $1.recordedAt }
    }
}
