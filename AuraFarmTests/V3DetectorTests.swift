import CoreML
import XCTest

@testable import AuraFarm

/// SoilDetector V3 opening out of the app bundle. It is the only model the app ships, and a
/// detection is read by name rather than by slot, so what matters is that the names the model
/// carries are the ones this app expects.
final class V3DetectorTests: XCTestCase {
    func testV3OpensAndNamesItsTwentyTwoClassesInOrder() throws {
        let detector = try OrganismDetector(model: .v3, computeUnits: .cpuAndGPU)

        XCTAssertEqual(detector.kind, .v3)
        XCTAssertEqual(detector.modelName, "SoilDetectorV3")
        XCTAssertEqual(detector.classNames.count, 23, "background and 22 classes")
        XCTAssertEqual(detector.classNames.first, "background")
        XCTAssertEqual(
            detector.classNames, DetectorModel.v3ClassNames,
            "the names the model carries are the built-in list")
    }

    /// V3's graph ends in a sigmoid, so applying another would put every query at 0.5 or more.
    func testV3ScoresArriveAsProbabilities() {
        XCTAssertEqual(DetectorModel.v3.scoresOutput, "scores")
        XCTAssertTrue(DetectorModel.v3.scoresAreProbabilities)
    }
}
