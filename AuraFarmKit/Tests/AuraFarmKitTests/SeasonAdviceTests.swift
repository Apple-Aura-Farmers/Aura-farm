import XCTest

@testable import AuraFarmKit

final class SeasonAdviceTests: XCTestCase {
    /// 2026-11-09 00:00 UTC.
    private static let today = Date(timeIntervalSince1970: 1_794_182_400)

    private static func result(organicCarbon: Double? = nil) -> NutrientResult {
        NutrientResult(
            testedAt: today.addingTimeInterval(-7 * 86_400),
            source: .laboratory,
            levels: [.nitrogen: .medium, .phosphorus: .medium, .potassium: .medium],
            straw: .removed,
            organicCarbonPercent: organicCarbon
        )
    }

    func testLowOrganicCarbonAsksForOrganicMatter() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(organicCarbon: 1.4), organisms: [], now: Self.today)
        )

        XCTAssertTrue(advice.actions.contains { $0.title == "Add organic matter before planting" })
    }

    func testEnoughOrganicCarbonNeedsNoAction() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(organicCarbon: 2.6), organisms: [], now: Self.today)
        )

        XCTAssertFalse(advice.actions.contains { $0.title.contains("organic matter") })
    }

    func testATransplantingDatePutsDatesOnEachDose() throws {
        let planted = Self.today
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(), organisms: [], plantedOn: planted, now: Self.today)
        )

        let urea = try XCTUnwrap(advice.doses.first { $0.fertilizer == .urea })
        XCTAssertEqual(urea.dates.map { Int($0.timeIntervalSince(planted) / 86_400) }, [3, 30, 50])
        let sp36 = try XCTUnwrap(advice.doses.first { $0.fertilizer == .sp36 })
        XCTAssertEqual(sp36.dates.count, 1)
    }

    func testWithoutATransplantingDateTheDosesHaveNoDates() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(), organisms: [], now: Self.today)
        )

        XCTAssertTrue(advice.doses.allSatisfy { $0.dates.isEmpty })
    }

    func testAppliedFertilizerIsCountedAgainstThePlan() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(), organisms: [], areaHectares: 0.5, now: Self.today)
        )

        let progress = FertilizerProgress.compare(
            doses: advice.doses,
            applied: [(.urea, 50), (.urea, 40), (.npkCompound, 100), (.kcl, 25)]
        )

        XCTAssertEqual(progress.map(\.fertilizer), [.urea, .sp36, .kcl])
        XCTAssertEqual(progress.map(\.appliedKilograms), [90, 0, 25])
        XCTAssertEqual(progress.map(\.plannedKilograms), [125, 37.5, 50])
        XCTAssertEqual(try XCTUnwrap(progress[2].shareApplied), 0.5, accuracy: 0.0001)
    }

    func testWithoutAnAreaThereIsNoShareApplied() throws {
        let advice = try XCTUnwrap(
            SoilAdvisor.advise(nutrients: Self.result(), organisms: [], now: Self.today)
        )

        let progress = FertilizerProgress.compare(doses: advice.doses, applied: [(.urea, 50)])

        XCTAssertNil(progress[0].plannedKilograms)
        XCTAssertNil(progress[0].shareApplied)
    }

    func testTotalHarvestTurnsIntoTonnesPerHectare() {
        XCTAssertEqual(HarvestYield.tonnesPerHectare(totalKilograms: 3_000, areaHectares: 0.5), 6)
        XCTAssertNil(HarvestYield.tonnesPerHectare(totalKilograms: 3_000, areaHectares: nil))
        XCTAssertNil(HarvestYield.tonnesPerHectare(totalKilograms: 3_000, areaHectares: 0))
    }
}
