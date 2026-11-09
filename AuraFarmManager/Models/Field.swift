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

    /// Deleting a field keeps its soil tests: they go back to the inbox to be filed again.
    @Relationship(deleteRule: .nullify, inverse: \SoilTest.field)
    var soilTests: [SoilTest] = []

    /// NPK results typed in for this field. They belong to it alone, so deleting the field
    /// deletes them.
    @Relationship(deleteRule: .cascade, inverse: \NutrientTest.field)
    var nutrientTests: [NutrientTest] = []

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

    /// The most recent NPK results, if any.
    var latestNutrientTest: NutrientTest? {
        nutrientTests.max { $0.testedAt < $1.testedAt }
    }

    /// NPK results, newest first.
    var sortedNutrientTests: [NutrientTest] {
        nutrientTests.sorted { $0.testedAt > $1.testedAt }
    }

    /// Soil tests, newest first.
    var sortedSoilTests: [SoilTest] {
        soilTests.sorted { $0.recordedAt > $1.recordedAt }
    }
}
