import XCTest

@testable import AuraFarmKit

final class FieldBoundaryTests: XCTestCase {
    /// About 100 m by 100 m near Jatiluwih, Bali: 1 ha.
    private static let hectare: FieldBoundary = {
        let latitude = -8.3700
        let longitude = 115.1300
        let metresPerDegree = FieldBoundary.earthRadiusMetres * .pi / 180
        let dLat = 100 / metresPerDegree
        let dLon = 100 / (metresPerDegree * cos(latitude * .pi / 180))
        return FieldBoundary(corners: [
            FieldPoint(latitude: latitude, longitude: longitude),
            FieldPoint(latitude: latitude, longitude: longitude + dLon),
            FieldPoint(latitude: latitude + dLat, longitude: longitude + dLon),
            FieldPoint(latitude: latitude + dLat, longitude: longitude),
        ])
    }()

    func testASquareHundredMetresAcrossIsOneHectare() throws {
        let area = try XCTUnwrap(Self.hectare.areaHectares)

        XCTAssertEqual(area, 1, accuracy: 0.001)
    }

    func testCornerOrderDoesNotChangeTheArea() throws {
        let reversed = FieldBoundary(corners: Self.hectare.corners.reversed())

        XCTAssertEqual(try XCTUnwrap(reversed.areaHectares), 1, accuracy: 0.001)
    }

    func testATriangleIsHalfTheSquare() throws {
        let triangle = FieldBoundary(corners: Array(Self.hectare.corners.prefix(3)))

        XCTAssertEqual(try XCTUnwrap(triangle.areaHectares), 0.5, accuracy: 0.001)
    }

    func testFewerThanThreeCornersHasNoArea() {
        let line = FieldBoundary(corners: Array(Self.hectare.corners.prefix(2)))

        XCTAssertFalse(line.isComplete)
        XCTAssertNil(line.areaHectares)
    }

    func testACornerOffTheEarthIsNotComplete() {
        var boundary = Self.hectare
        boundary.corners[0].latitude = 120

        XCTAssertFalse(boundary.isComplete)
    }

    func testEncodingRoundTrips() throws {
        let decoded = FieldBoundary(data: try Self.hectare.encoded())

        XCTAssertEqual(decoded, Self.hectare)
    }

    func testOtherDataIsNotABoundary() {
        XCTAssertNil(FieldBoundary(data: Data("not a boundary".utf8)))
    }

    func testBoundsHoldEveryCornerAndUnionHoldsEveryBox() throws {
        let first = try XCTUnwrap(Self.hectare.bounds)
        let moved = FieldBoundary(corners: Self.hectare.corners.map {
            FieldPoint(latitude: $0.latitude - 0.01, longitude: $0.longitude + 0.01)
        })
        let second = try XCTUnwrap(moved.bounds)

        let union = try XCTUnwrap(GeoBounds.union([first, second]))

        XCTAssertEqual(union.maxLatitude, first.maxLatitude)
        XCTAssertEqual(union.minLatitude, second.minLatitude)
        XCTAssertEqual(union.minLongitude, first.minLongitude)
        XCTAssertEqual(union.maxLongitude, second.maxLongitude)
        XCTAssertNil(GeoBounds.union([]))
    }

    func testASmallFieldIsNotZoomedPastTheMinimumSpan() throws {
        let span = try XCTUnwrap(Self.hectare.bounds).span()

        XCTAssertGreaterThanOrEqual(span.latitude, 0.002)
        XCTAssertGreaterThanOrEqual(span.longitude, 0.002)
    }
}
