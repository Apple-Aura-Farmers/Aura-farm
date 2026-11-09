import Foundation

/// One set of NPK results for a field, as the advisor reads it.
public struct NutrientResult: Equatable, Sendable {
    public var testedAt: Date
    public var source: NutrientSource
    /// The class of each nutrient that was tested. A nutrient left out was not tested.
    public var levels: [Nutrient: NutrientLevel]
    /// pH in water, when it was measured.
    public var pH: Double?
    public var straw: StrawPractice

    public init(
        testedAt: Date,
        source: NutrientSource,
        levels: [Nutrient: NutrientLevel],
        pH: Double? = nil,
        straw: StrawPractice = .unknown
    ) {
        self.testedAt = testedAt
        self.source = source
        self.levels = levels
        self.pH = pH
        self.straw = straw
    }
}

/// One microscope soil test, reduced to what the advisor compares.
public struct OrganismCountSummary: Equatable, Sendable {
    public var recordedAt: Date
    /// Every organism counted, across all groups.
    public var total: Int
    /// Tests are compared only when this matches: how the slide was made, how much soil, how
    /// much was scanned. Raw counts from slides made differently say nothing about each other.
    public var preparationKey: String

    public init(recordedAt: Date, total: Int, preparationKey: String) {
        self.recordedAt = recordedAt
        self.total = total
        self.preparationKey = preparationKey
    }
}
