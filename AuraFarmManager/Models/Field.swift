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
}
