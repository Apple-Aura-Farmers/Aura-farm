import AuraFarmKit
import Foundation

/// Hands a field's records to the shared advisor and returns what to do about the field.
enum FieldAdvice {
    /// nil when the field has neither NPK results nor soil tests.
    @MainActor
    static func advice(for field: Field, now: Date = .now) -> SoilAdvice? {
        SoilAdvisor.advise(
            nutrients: field.latestNutrientTest?.result,
            organisms: field.soilTests.map(summary(of:)),
            areaHectares: field.areaHectares,
            plantedOn: field.currentSeason?.plantedOn,
            now: now
        )
    }

    /// A soil test reduced to what the advisor compares. Two tests share a preparation key only
    /// when the slide was made the same way from the same amounts.
    static func summary(of test: SoilTest) -> OrganismCountSummary {
        let amounts = [test.gramsOfSoil, test.millilitresOfWater, test.millilitresScanned]
            .map { $0.map { String($0) } ?? "-" }
        let key = ([test.preparation.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] + amounts)
            .joined(separator: "|")
        return OrganismCountSummary(recordedAt: test.recordedAt, total: test.totalCount, preparationKey: key)
    }
}
