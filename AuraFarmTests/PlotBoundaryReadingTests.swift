import XCTest

@testable import AuraFarm

/// Reading a boundary back out of the records, which hands it over as hex well-known binary
/// rather than as the text it went up as.
final class PlotBoundaryReadingTests: XCTestCase {
    private let corners = [
        GeoPoint(latitude: -8.4095, longitude: 115.1889),
        GeoPoint(latitude: -8.4095, longitude: 115.1900),
        GeoPoint(latitude: -8.4105, longitude: 115.1900),
    ]

    func testAPolygonComesBackWithTheCornersItWentUpWith() throws {
        let read = try XCTUnwrap(PlotBoundary.corners(fromHexBinary: hex(closing(corners))))

        XCTAssertEqual(read.count, corners.count)
        for (read, sent) in zip(read, corners) {
            XCTAssertEqual(read.latitude, sent.latitude, accuracy: 0.000_000_1)
            XCTAssertEqual(read.longitude, sent.longitude, accuracy: 0.000_000_1)
        }
    }

    func testTheCornerThatClosesTheRingIsDropped() throws {
        // The map holds its corners open, so a fourth corner on top of the first would be one
        // the helper could drag away from the shape.
        let read = try XCTUnwrap(PlotBoundary.corners(fromHexBinary: hex(closing(corners))))

        XCTAssertNotEqual(read.first, read.last)
    }

    func testTheBytesSayWhichWayRoundTheyAreRead() throws {
        let little = try XCTUnwrap(PlotBoundary.corners(fromHexBinary: hex(closing(corners))))
        let big = try XCTUnwrap(
            PlotBoundary.corners(fromHexBinary: hex(closing(corners), littleEndian: false)))

        XCTAssertEqual(little, big)
    }

    func testAShapeThatIsNotAPolygonIsNotRead() {
        // 1 is a point, which the phone has no way to draw as land.
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: hex(closing(corners), type: 1)))
    }

    func testRubbishIsTurnedAwayRatherThanGuessedAt() {
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: ""))
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: "nonsense"))
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: "0103"))
        // A ring cut short partway through its last corner.
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: String(hex(closing(corners)).dropLast(4))))
    }

    func testAPolygonOfTooFewCornersIsNotLand() {
        let line = [corners[0], corners[1]]
        XCTAssertNil(PlotBoundary.corners(fromHexBinary: hex(line)))
    }

    // MARK: Building what PostGIS would send

    private func closing(_ ring: [GeoPoint]) -> [GeoPoint] {
        ring + [ring[0]]
    }

    /// The bytes PostGIS hands over for a polygon of one ring: byte order, the type with its
    /// SRID flag, the SRID, the ring count, the corner count, then longitude and latitude.
    private func hex(
        _ ring: [GeoPoint], littleEndian: Bool = true, type: UInt32 = 3
    ) -> String {
        var bytes: [UInt8] = [littleEndian ? 1 : 0]

        func append(_ value: UInt32) {
            let raw = littleEndian ? value : value.byteSwapped
            bytes.append(contentsOf: (0..<4).map { UInt8((raw >> ($0 * 8)) & 0xFF) })
        }
        func append(_ value: Double) {
            let raw = littleEndian ? value.bitPattern : value.bitPattern.byteSwapped
            bytes.append(contentsOf: (0..<8).map { UInt8((raw >> ($0 * 8)) & 0xFF) })
        }

        append(type | 0x2000_0000)
        append(UInt32(4326))
        append(UInt32(1))
        append(UInt32(ring.count))
        for corner in ring {
            append(corner.longitude)
            append(corner.latitude)
        }
        return bytes.map { String(format: "%02X", $0) }.joined()
    }
}
