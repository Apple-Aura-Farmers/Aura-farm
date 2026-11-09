import Foundation
import SwiftData

/// A farm the field helpers visit, and the fields it is split into.
@Model
final class Farm {
    var name: String
    /// The farmer the results are explained to.
    var ownerName: String
    /// Village or district, the way the team refers to it.
    var location: String
    var notes: String
    var createdAt: Date

    /// Deleting a farm deletes its fields. Their soil tests are kept and go back to the inbox.
    @Relationship(deleteRule: .cascade, inverse: \Field.farm)
    var fields: [Field] = []

    init(
        name: String,
        ownerName: String = "",
        location: String = "",
        notes: String = "",
        createdAt: Date = .now
    ) {
        self.name = name
        self.ownerName = ownerName
        self.location = location
        self.notes = notes
        self.createdAt = createdAt
    }

    /// Fields in the order a person would list them: "Field 2" before "Field 10".
    var sortedFields: [Field] {
        fields.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Every soil test filed under one of this farm's fields, newest first.
    var soilTests: [SoilTest] {
        fields.flatMap(\.soilTests).sorted { $0.recordedAt > $1.recordedAt }
    }
}
