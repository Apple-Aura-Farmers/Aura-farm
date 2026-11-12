import XCTest

@testable import AuraFarm

final class ViewClassifierTests: XCTestCase {
    private func classify(_ brightness: Double, _ sharpness: Double, times: Int = 3) -> ViewClassifier {
        var classifier = ViewClassifier()
        for _ in 0..<times { classifier.update(brightness: brightness, sharpness: sharpness, contrast: 20) }
        return classifier
    }

    func testEachClassWithoutABaseline() {
        XCTAssertEqual(classify(20, 2000).current, .dark)
        XCTAssertEqual(classify(180, 2000).current, .sample)
        XCTAssertEqual(classify(180, 200).current, .thin)
        XCTAssertEqual(classify(212, 40).current, .blank, "bright and featureless")
        XCTAssertEqual(classify(150, 40).current, .blurry, "featureless but not bright")
    }

    func testTheFirstReadingSetsTheClassDirectly() {
        var classifier = ViewClassifier()
        XCTAssertEqual(classifier.update(brightness: 212, sharpness: 40, contrast: 5), .blank)
    }

    func testATwoReadingFlickerDoesNotChangeTheClass() {
        var classifier = classify(180, 2000)
        classifier.update(brightness: 212, sharpness: 40, contrast: 5)
        classifier.update(brightness: 212, sharpness: 40, contrast: 5)
        XCTAssertEqual(classifier.current, .sample)
        XCTAssertEqual(classifier.rawClass, .blank)
        classifier.update(brightness: 180, sharpness: 2000, contrast: 20)
        classifier.update(brightness: 212, sharpness: 40, contrast: 5)
        classifier.update(brightness: 212, sharpness: 40, contrast: 5)
        XCTAssertEqual(classifier.current, .sample, "the streak was broken")
        classifier.update(brightness: 212, sharpness: 40, contrast: 5)
        XCTAssertEqual(classifier.current, .blank)
    }

    func testBlankAndBlurryAreSeparatedByBrightnessAgainstTheBaseline() {
        var classifier = classify(120, 2000, times: 5)  // a dim exposure: baseline 120
        XCTAssertEqual(try XCTUnwrap(classifier.baseline), 120, accuracy: 0.001)
        // 150 would be blurry against the fallback (195) but is blank against 120 * 1.15 = 138.
        for _ in 0..<3 { classifier.update(brightness: 150, sharpness: 40, contrast: 5) }
        XCTAssertEqual(classifier.current, .blank)
        for _ in 0..<3 { classifier.update(brightness: 125, sharpness: 40, contrast: 5) }
        XCTAssertEqual(classifier.current, .blurry)
    }

    func testTheBaselineFollowsTheExposure() {
        var classifier = ViewClassifier()
        for _ in 0..<30 { classifier.update(brightness: 170, sharpness: 2000, contrast: 20) }
        XCTAssertEqual(try XCTUnwrap(classifier.baseline), 170, accuracy: 0.001)
        for _ in 0..<30 { classifier.update(brightness: 100, sharpness: 2000, contrast: 20) }
        XCTAssertEqual(try XCTUnwrap(classifier.baseline), 100, accuracy: 0.001, "20 readings kept")
    }

    func testOnlySampleReadingsFeedTheBaseline() {
        var classifier = classify(212, 40)
        XCTAssertNil(classifier.baseline)
        classifier.update(brightness: 180, sharpness: 200, contrast: 5)
        XCTAssertNil(classifier.baseline, "thin sample is not baseline material")
        classifier.reset()
        XCTAssertFalse(classifier.hasReading)
    }
}
