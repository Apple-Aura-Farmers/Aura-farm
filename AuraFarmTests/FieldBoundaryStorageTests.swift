import AuraFarmKit
import SwiftData
import XCTest

@testable import AuraFarm

@MainActor
final class FieldBoundaryStorageTests: XCTestCase {
    private static let triangle = FieldBoundary(corners: [
        FieldPoint(latitude: -8.3700, longitude: 115.1300),
        FieldPoint(latitude: -8.3700, longitude: 115.1310),
        FieldPoint(latitude: -8.3690, longitude: 115.1310),
    ])

    func testAnOutlineIsKeptWithTheField() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let field = Field(name: "North paddy")
        container.mainContext.insert(field)

        field.boundary = Self.triangle
        try container.mainContext.save()

        XCTAssertEqual(field.boundary, Self.triangle)
        XCTAssertNotNil(field.boundaryData)
    }

    func testAnOutlineWithTooFewCornersRemovesIt() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let field = Field(name: "North paddy")
        container.mainContext.insert(field)
        field.boundary = Self.triangle

        field.boundary = FieldBoundary(corners: Array(Self.triangle.corners.prefix(2)))

        XCTAssertNil(field.boundary)
        XCTAssertNil(field.boundaryData)
    }

    func testTheMapRegionTakesInEveryDrawnField() throws {
        let container = try FarmStore.makeContainer(inMemory: true)
        let drawn = Field(name: "North paddy")
        let undrawn = Field(name: "River paddy")
        container.mainContext.insert(drawn)
        container.mainContext.insert(undrawn)
        drawn.boundary = Self.triangle

        let region = try XCTUnwrap(MapDefaults.region(around: [drawn, undrawn]))

        XCTAssertEqual(region.center.latitude, -8.3695, accuracy: 0.0001)
        XCTAssertNil(MapDefaults.region(around: [undrawn]))
    }
}
