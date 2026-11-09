import Foundation
import SwiftData

/// Where the farm records are kept: a SwiftData store in the app's container.
enum FarmStore {
    static let models: [any PersistentModel.Type] = [
        Farm.self,
        Field.self,
        SoilTest.self,
        OrganismCount.self,
        NutrientTest.self,
    ]

    /// - Parameter inMemory: true for tests and previews, so nothing is written to disk.
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
