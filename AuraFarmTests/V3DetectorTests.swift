import CoreML
import XCTest

@testable import AuraFarm

/// SoilDetector V3 opening out of the app bundle, and the one thing that sets it apart from V2:
/// the export drops Stentor, so its class list is one shorter and everything after that slot has
/// moved. A detection is read by name rather than by index, so what matters is that the names the
/// model carries are the ones this app expects.
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

    func testV3IsV2WithoutStentor() {
        XCTAssertFalse(DetectorModel.v3ClassNames.contains("Stentor"))
        XCTAssertTrue(DetectorModel.v2ClassNames.contains("Stentor"))
        XCTAssertEqual(
            DetectorModel.v2ClassNames.filter { $0 != "Stentor" }, DetectorModel.v3ClassNames,
            "nothing else changed between the two exports")
    }

    /// V1's scores are logits and need a sigmoid; V2's and V3's graphs end in one already, so
    /// applying another would put every query at 0.5 or more.
    func testV3ScoresAreReadTheSameWayAsV2s() {
        XCTAssertEqual(DetectorModel.v3.scoresOutput, "scores")
        XCTAssertTrue(DetectorModel.v3.scoresAreProbabilities)
        XCTAssertFalse(DetectorModel.v1.scoresAreProbabilities)
    }
}
