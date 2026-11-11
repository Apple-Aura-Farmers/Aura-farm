import XCTest

@testable import AuraFarm

final class PlotBoundaryTests: XCTestCase {
    private let bali = [
        GeoPoint(latitude: -8.5, longitude: 115.1),
        GeoPoint(latitude: -8.5, longitude: 115.2),
        GeoPoint(latitude: -8.6, longitude: 115.2),
    ]

    func testTheRingComesBackToWhereItStarted() {
        // PostGIS rejects a polygon whose ring is left open.
        let text = PlotBoundary.wellKnownText(for: bali)

        XCTAssertEqual(
            text,
            "SRID=4326;POLYGON((115.10000000 -8.50000000, 115.20000000 -8.50000000, "
                + "115.20000000 -8.60000000, 115.10000000 -8.50000000))"
        )
    }

    func testLongitudeComesBeforeLatitude() {
        // The classic way to put a Bali paddy field in the Indian Ocean.
        let text = PlotBoundary.wellKnownText(for: bali) ?? ""

        XCTAssertTrue(text.contains("((115."), text)
    }

    func testCornersThatCannotEncloseAnythingAreRefused() {
        XCTAssertNil(PlotBoundary.wellKnownText(for: []))
        XCTAssertNil(PlotBoundary.wellKnownText(for: Array(bali.prefix(2))))
    }

    func testARingThatIsAlreadyClosedIsNotClosedTwice() {
        let closed = bali + [bali[0]]

        let text = PlotBoundary.wellKnownText(for: closed) ?? ""

        XCTAssertEqual(text.components(separatedBy: ",").count, 4)
    }

    func testSmallNumbersStayAsDigitsRatherThanBecomingExponents() {
        // Double's own description writes 1e-05, which is not well-known text.
        let nearZero = [
            GeoPoint(latitude: 0.00001, longitude: 0.00002),
            GeoPoint(latitude: 0.00001, longitude: 0.00003),
            GeoPoint(latitude: 0.00002, longitude: 0.00003),
        ]

        let text = PlotBoundary.wellKnownText(for: nearZero) ?? ""

        XCTAssertFalse(text.lowercased().contains("e-"), text)
    }

    func testTheAreaIsTheOneTheHelperWasShown() {
        let hectares = PlotBoundary.hectares(of: bali)
        let squareMetres = LandGeometry.areaSquareMetres(of: bali)

        XCTAssertNotNil(hectares)
        XCTAssertEqual(hectares ?? 0, (squareMetres ?? 0) / 10_000, accuracy: 0.001)
    }
}
