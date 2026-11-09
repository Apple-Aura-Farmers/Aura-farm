import AuraFarmKit
import SwiftData
import XCTest

@testable import AuraFarmManager

@MainActor
final class NutrientTestTests: XCTestCase {
    func testResultsCarryEachTestedNutrientAndLeaveOutTheRest() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let test = NutrientTest(testedAt: Self.day(0), source: .laboratory)
        container.mainContext.insert(test)
        test.setLevel(.low, of: .nitrogen)
        test.setLevel(.high, of: .potassium)
        test.straw = .returned
        test.pH = 5.8

        let result = test.result

        XCTAssertEqual(result.levels, [.nitrogen: .low, .potassium: .high])
        XCTAssertEqual(result.source, .laboratory)
        XCTAssertEqual(result.straw, .returned)
        XCTAssertEqual(result.pH, 5.8)
    }

    func testALabValueKeepsItsUnitAndCanBeCleared() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let test = NutrientTest(testedAt: Self.day(0), source: .laboratory)
        container.mainContext.insert(test)

        test.setMeasurement((value: 32, unit: .phosphatePerHundredGramsHCl), of: .phosphorus)
        XCTAssertEqual(test.measurement(of: .phosphorus)?.value, 32)
        XCTAssertEqual(test.measurement(of: .phosphorus)?.unit, .phosphatePerHundredGramsHCl)

        test.setMeasurement(nil, of: .phosphorus)
        XCTAssertNil(test.measurement(of: .phosphorus))
    }

    func testDeletingAFieldDeletesItsNPKResults() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let field = Field(name: "North paddy")
        let test = NutrientTest(testedAt: Self.day(0), source: .soilTestKit)
        context.insert(field)
        context.insert(test)
        test.field = field
        try context.save()
        XCTAssertEqual(field.nutrientTests.count, 1)

        context.delete(field)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<NutrientTest>()), 0)
    }

    func testAdviceUsesTheLatestNPKResultsAndTheFieldArea() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let field = Field(name: "North paddy", areaHectares: 0.5)
        context.insert(field)
        let older = Self.kitTest(on: Self.day(-60), nitrogen: .high, in: context)
        let newer = Self.kitTest(on: Self.day(-5), nitrogen: .low, in: context)
        older.field = field
        newer.field = field
        try context.save()

        let advice = try XCTUnwrap(FieldAdvice.advice(for: field, now: Self.day(0)))

        let urea = try XCTUnwrap(advice.doses.first { $0.fertilizer == .urea })
        XCTAssertEqual(urea.level, .low)
        XCTAssertEqual(urea.kilogramsPerHectare, 300)
        XCTAssertEqual(urea.kilogramsForField, 150)
    }

    func testAFieldWithNothingOnItHasNoAdvice() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let field = Field(name: "North paddy")
        container.mainContext.insert(field)

        XCTAssertNil(FieldAdvice.advice(for: field, now: Self.day(0)))
    }

    // MARK: - Fixtures

    /// Days from 2026-11-09 00:00 UTC.
    private static func day(_ offset: Double) -> Date {
        Date(timeIntervalSince1970: 1_794_182_400 + offset * 86_400)
    }

    private static func kitTest(
        on date: Date,
        nitrogen: NutrientLevel,
        in context: ModelContext
    ) -> NutrientTest {
        let test = NutrientTest(testedAt: date, source: .soilTestKit)
        context.insert(test)
        test.setLevel(nitrogen, of: .nitrogen)
        test.setLevel(.medium, of: .phosphorus)
        test.setLevel(.medium, of: .potassium)
        return test
    }
}
