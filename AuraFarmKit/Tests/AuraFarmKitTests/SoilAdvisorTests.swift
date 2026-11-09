import XCTest

@testable import AuraFarmKit

final class SoilAdvisorTests: XCTestCase {
    /// 2026-11-09 00:00 UTC.
    private static let today = Date(timeIntervalSince1970: 1_794_182_400)

    func testNothingToGoOnGivesNoAdvice() {
        XCTAssertNil(SoilAdvisor.advise(nutrients: nil, organisms: [], now: Self.today))
    }

    func testLowNutrientsGetTheLargestDoses() throws {
        let advice = try Self.advise(Self.result(n: .low, p: .low, k: .low))

        XCTAssertEqual(advice.doses.map(\.fertilizer), [.urea, .sp36, .kcl])
        XCTAssertEqual(advice.doses.map(\.kilogramsPerHectare), [300, 100, 100])
    }

    func testHighNutrientsGetTheSmallestDoses() throws {
        let advice = try Self.advise(Self.result(n: .high, p: .high, k: .high))

        XCTAssertEqual(advice.doses.map(\.kilogramsPerHectare), [200, 50, 50])
    }

    func testReturnedStrawHalvesPotashOnLowAndMediumK() {
        XCTAssertEqual(PaddyFertilizerGuide.kclKilogramsPerHectare(potassium: .low, straw: .returned), 50)
        XCTAssertEqual(
            PaddyFertilizerGuide.kclKilogramsPerHectare(potassium: .medium, straw: .returned), 50
        )
        XCTAssertEqual(
            PaddyFertilizerGuide.kclKilogramsPerHectare(potassium: .medium, straw: .removed), 100
        )
    }

    func testUnknownStrawIsTreatedAsRemovedAndSaysSo() throws {
        let advice = try Self.advise(Self.result(k: .medium))

        XCTAssertEqual(advice.doses.first { $0.fertilizer == .kcl }?.kilogramsPerHectare, 100)
        XCTAssertTrue(advice.basis.contains { $0.contains("Straw not recorded") })
    }

    func testFieldAreaGivesTheDoseForTheWholeField() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(
                nutrients: Self.result(n: .medium, p: .medium, k: .medium, straw: .removed),
                organisms: [],
                areaHectares: 0.5,
                now: Self.today
            )
        )

        XCTAssertEqual(advice.doses.map(\.kilogramsForField), [125, 37.5, 50])
    }

    func testAnUntestedNutrientGetsNoDoseAndAnActionToTestIt() throws {
        let advice = try Self.advise(Self.result(n: .low, p: nil, k: .low))

        XCTAssertEqual(advice.doses.map(\.fertilizer), [.urea, .kcl])
        XCTAssertTrue(advice.actions.contains { $0.kind == .testing && $0.title.contains("phosphorus") })
    }

    func testLabResultsAreTrustedMoreThanAKit() throws {
        let kit = try Self.advise(Self.result(source: .soilTestKit))
        let lab = try Self.advise(Self.result(source: .laboratory))

        XCTAssertEqual(kit.confidence.level, .fair)
        XCTAssertEqual(lab.confidence.level, .good)
    }

    func testOldResultsLowerTheConfidence() throws {
        let old = Self.today.addingTimeInterval(-200 * 86_400)
        let advice = try Self.advise(Self.result(testedAt: old))

        XCTAssertEqual(advice.confidence.level, .low)
        XCTAssertTrue(advice.confidence.reasons.contains { $0.contains("200 days") })
    }

    func testEveryPlanSaysWhenToTestAgain() throws {
        let advice = try Self.advise(Self.result())

        XCTAssertFalse(advice.retests.isEmpty)
        XCTAssertFalse(advice.confidence.reasons.isEmpty)
    }

    func testAcidSoilAsksForALabTestAndTheExtensionOfficer() throws {
        let advice = try Self.advise(Self.result(pH: 5.0))

        XCTAssertTrue(advice.actions.contains { $0.kind == .soil && $0.title.contains("liming") })
        XCTAssertTrue(advice.retests.contains { $0.contains("lab") })
    }

    func testNeutralSoilNeedsNoPHAction() throws {
        let advice = try Self.advise(Self.result(pH: 7.0))

        XCTAssertFalse(advice.actions.contains { $0.kind == .soil })
    }

    func testPHBands() {
        XCTAssertEqual(SoilAcidity(pH: 4.2), .veryAcidic)
        XCTAssertEqual(SoilAcidity(pH: 5.0), .acidic)
        XCTAssertEqual(SoilAcidity(pH: 6.0), .slightlyAcidic)
        XCTAssertEqual(SoilAcidity(pH: 6.5), .neutral)
        XCTAssertEqual(SoilAcidity(pH: 8.0), .alkaline)
    }

    func testCountsWithoutNPKAskForAnNPKTest() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(
                nutrients: nil,
                organisms: [Self.count(40, daysAgo: 1)],
                now: Self.today
            )
        )

        XCTAssertTrue(advice.doses.isEmpty)
        XCTAssertEqual(advice.confidence.level, .low)
        XCTAssertTrue(advice.actions.contains { $0.kind == .testing })
    }

    func testAnEmptySlideAsksForTheSlideToBeChecked() {
        let actions = SoilAdvisor.organismActions(
            for: [Self.count(0, daysAgo: 1), Self.count(30, daysAgo: 40)]
        )

        XCTAssertEqual(actions.map(\.title), ["Check the slide and test again"])
    }

    func testABigDropAgainstTheSamePreparationAsksForARepeat() {
        let actions = SoilAdvisor.organismActions(
            for: [Self.count(40, daysAgo: 40), Self.count(12, daysAgo: 1)]
        )

        XCTAssertEqual(actions.map(\.title), ["Repeat the microscope test"])
    }

    func testADropAgainstADifferentPreparationIsNotCompared() {
        let actions = SoilAdvisor.organismActions(
            for: [Self.count(40, daysAgo: 40, preparation: "1 g in 10 ml"), Self.count(12, daysAgo: 1)]
        )

        XCTAssertTrue(actions.isEmpty)
    }

    func testSmallCountsAreNotCompared() {
        let actions = SoilAdvisor.organismActions(
            for: [Self.count(6, daysAgo: 40), Self.count(2, daysAgo: 1)]
        )

        XCTAssertTrue(actions.isEmpty)
    }

    func testLabValuesAreClassedByTheirUnit() {
        XCTAssertEqual(NutrientThresholds.level(of: 15, in: .phosphatePerHundredGramsHCl), .low)
        XCTAssertEqual(NutrientThresholds.level(of: 30, in: .phosphatePerHundredGramsHCl), .medium)
        XCTAssertEqual(NutrientThresholds.level(of: 45, in: .phosphatePerHundredGramsHCl), .high)
        XCTAssertEqual(NutrientThresholds.level(of: 8, in: .potashPerHundredGramsHCl), .low)
        XCTAssertEqual(NutrientThresholds.level(of: 25, in: .potashPerHundredGramsHCl), .high)
        XCTAssertEqual(NutrientThresholds.level(of: 0.219, in: .totalNitrogenPercent), .medium)
        XCTAssertNil(NutrientThresholds.level(of: 12, in: .other))
    }

    func testPHReadsWithOneDecimal() {
        XCTAssertEqual(SoilAdvisor.oneDecimal(5.44), "5.4")
        XCTAssertEqual(SoilAdvisor.oneDecimal(6.0), "6.0")
    }

    // MARK: - Fixtures

    private static func advise(_ result: NutrientResult) throws -> SoilAdvice {
        try XCTUnwrap(SoilAdvisor.advise(nutrients: result, organisms: [], now: today))
    }

    private static func result(
        n: NutrientLevel? = .medium,
        p: NutrientLevel? = .medium,
        k: NutrientLevel? = .medium,
        source: NutrientSource = .soilTestKit,
        pH: Double? = nil,
        straw: StrawPractice = .unknown,
        testedAt: Date = SoilAdvisorTests.today.addingTimeInterval(-7 * 86_400)
    ) -> NutrientResult {
        var levels: [Nutrient: NutrientLevel] = [:]
        levels[.nitrogen] = n
        levels[.phosphorus] = p
        levels[.potassium] = k
        return NutrientResult(testedAt: testedAt, source: source, levels: levels, pH: pH, straw: straw)
    }

    private static func count(
        _ total: Int,
        daysAgo: Double,
        preparation: String = "0.5 g in 5 ml"
    ) -> OrganismCountSummary {
        OrganismCountSummary(
            recordedAt: Self.today.addingTimeInterval(-daysAgo * 86_400),
            total: total,
            preparationKey: preparation
        )
    }
}
