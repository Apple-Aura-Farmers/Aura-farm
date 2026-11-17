import XCTest

@testable import AuraFarm

/// Phase 2u part C: the straight-line fit through the confirmed top and bottom edge points.
final class EdgePredictionTests: XCTestCase {
    func testNoPredictionBeforeTwoPoints() {
        var prediction = EdgePrediction()
        XCTAssertNil(prediction.along(.bottom, at: 1))
        prediction.record(.bottom, x: 0.6, along: 9)
        XCTAssertNil(prediction.along(.bottom, at: 1))
        XCTAssertNil(prediction.along(.top, at: 1))
    }

    func testTwoBottomPointsGiveTheLineThroughThem() throws {
        var prediction = EdgePrediction()
        prediction.record(.bottom, x: 0.6, along: 9.0)
        prediction.record(.bottom, x: 2.2, along: 9.4)
        let fit = try XCTUnwrap(prediction.fit(.bottom))
        XCTAssertEqual(fit.slope, 0.25, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(prediction.along(.bottom, at: 3.8)), 9.8, accuracy: 1e-9)
    }

    func testAnOutlierIsDroppedWithThreeOrMorePoints() throws {
        var prediction = EdgePrediction()
        for (x, along) in [(0.6, 9.0), (2.2, 9.0), (3.8, 9.0), (5.4, 11.0), (7.0, 9.0)] {
            prediction.record(.bottom, x: x, along: along)
        }
        XCTAssertEqual(try XCTUnwrap(prediction.along(.bottom, at: 4.0)), 9.0, accuracy: 1e-9)
    }

    func testAPointWithinTheToleranceIsKept() throws {
        var prediction = EdgePrediction()
        for (x, along) in [(0.6, 9.0), (2.2, 9.0), (3.8, 9.6)] { prediction.record(.top, x: x, along: along) }
        let fit = try XCTUnwrap(prediction.fit(.top))
        XCTAssertGreaterThan(fit.slope, 0, "all three points are fitted")
    }

    func testMeanHeightIsTheTopToBottomDistanceOverTheColumns() throws {
        var prediction = EdgePrediction()
        prediction.record(.top, x: 0.6, along: 0)
        prediction.record(.top, x: 2.2, along: 0)
        prediction.record(.bottom, x: 0.6, along: 5.6)
        prediction.record(.bottom, x: 2.2, along: 5.6)
        XCTAssertEqual(try XCTUnwrap(prediction.meanHeight(atColumns: [0.6, 2.2])), 5.6, accuracy: 1e-9)
        XCTAssertNil(EdgePrediction().meanHeight(atColumns: [0.6]))
    }
}
