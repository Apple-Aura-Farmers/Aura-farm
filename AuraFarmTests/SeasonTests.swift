import AuraFarmKit
import SwiftData
import XCTest

@testable import AuraFarm

@MainActor
final class SeasonTests: XCTestCase {
    func testTheCurrentSeasonIsTheNewestNotYetHarvested() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let field = Field(name: "North paddy")
        context.insert(field)
        let dry = Self.season("Dry season 2026", plantedOn: Self.day(-150), in: context)
        let wet = Self.season("Wet season 2026–27", plantedOn: Self.day(-5), in: context)
        dry.field = field
        wet.field = field
        dry.harvestedOn = Self.day(-40)

        XCTAssertEqual(field.currentSeason?.name, "Wet season 2026–27")
        XCTAssertEqual(field.sortedSeasons.map(\.name), ["Wet season 2026–27", "Dry season 2026"])

        wet.harvestedOn = Self.day(0)
        XCTAssertNil(field.currentSeason)
    }

    func testThePlanIsDatedFromTheCurrentSeasonsTransplanting() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let field = Field(name: "North paddy", areaHectares: 0.5)
        context.insert(field)
        let test = NutrientTest(testedAt: Self.day(-10), source: .soilTestKit)
        context.insert(test)
        test.setLevel(.medium, of: .nitrogen)
        test.field = field
        let season = Self.season("Wet season 2026–27", plantedOn: Self.day(-5), in: context)
        season.field = field

        let advice = try XCTUnwrap(FieldAdvice.advice(for: field, now: Self.day(0)))

        let urea = try XCTUnwrap(advice.doses.first)
        XCTAssertEqual(urea.dates.first, Self.day(-2))
    }

    func testFertilizerPutOnIsCountedAgainstThePlan() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let season = Self.season("Wet season 2026–27", plantedOn: Self.day(-30), in: context)
        for (product, kilograms) in [(AppliedProduct.urea, 40.0), (.urea, 35), (.npkCompound, 100)] {
            let application = FertilizerApplication(
                appliedOn: Self.day(-20),
                product: product,
                kilograms: kilograms
            )
            context.insert(application)
            application.season = season
        }
        let dose = FertilizerDose(
            fertilizer: .urea,
            level: .medium,
            kilogramsPerHectare: 250,
            kilogramsForField: 125,
            schedule: ""
        )

        let progress = FertilizerProgress.compare(doses: [dose], applied: season.appliedAmounts)

        XCTAssertEqual(progress.first?.appliedKilograms, 75)
        XCTAssertEqual(progress.first?.plannedKilograms, 125)
    }

    func testDeletingAFieldDeletesItsSeasonsAndTheirFertilizer() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let field = Field(name: "North paddy")
        context.insert(field)
        let season = Self.season("Wet season 2026–27", plantedOn: nil, in: context)
        season.field = field
        let application = FertilizerApplication(appliedOn: Self.day(0), product: .urea, kilograms: 50)
        context.insert(application)
        application.season = season
        try context.save()

        context.delete(field)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Season>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FertilizerApplication>()), 0)
    }

    func testSuggestedSeasonNamesFollowBalisWetAndDrySeasons() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Makassar"))
        func date(_ year: Int, _ month: Int) throws -> Date {
            try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: 15)))
        }

        let name = { (date: Date) in SeasonEditorView.suggestedName(for: date, calendar: calendar) }

        XCTAssertEqual(name(try date(2026, 11)), "Wet season 2026–27")
        XCTAssertEqual(name(try date(2027, 2)), "Wet season 2026–27")
        XCTAssertEqual(name(try date(2027, 7)), "Dry season 2027")
    }

    // MARK: - Fixtures

    /// Days from 2026-11-09 00:00 UTC.
    private static func day(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 1_794_182_400 + offset * 86_400)
    }

    private static func season(_ name: String, plantedOn: Date?, in context: ModelContext) -> Season {
        let season = Season(name: name, plantedOn: plantedOn)
        context.insert(season)
        return season
    }
}
