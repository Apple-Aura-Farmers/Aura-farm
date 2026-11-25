import XCTest

@testable import AuraFarm

/// The guided scan's engine and page are release code (no `#if DEBUG`): this file compiles in
/// the test target either way, and the app's Release build compiles the same sources.
final class GuidedScanReleaseTests: XCTestCase {
    func testTheEngineAndThePageAreNotDebugOnly() {
        // Named outside any `#if DEBUG`: the Release build of the app has to contain them.
        XCTAssertTrue(ScanEngine.self is NSObject.Type)
        XCTAssertNotNil(GuidedScanPage.self as Any.Type)
        XCTAssertNotNil(LabSettingsSync.self as Any.Type)
        XCTAssertNotNil(LiveSetupOverlay.self as Any.Type)
        XCTAssertNotNil(GuidedScanSession.self as Any.Type)
    }

    func testTheReleaseDefaultsAreTheChosenSettings() {
        let release = LabSettings.releaseDefaults
        XCTAssertEqual(release.spotMode, .briefTouch)
        XCTAssertEqual(release.coverageStep, 1.6)
        XCTAssertEqual(release.detectorModelName, DetectorModel.v3.rawValue)
        XCTAssertEqual(release.detectorUnitsName, DetectorUnits.neuralEngine.rawValue)
        XCTAssertEqual(release.cameraRateName, CameraRate.fps20.rawValue)
        XCTAssertTrue(release.cropsToEyepiece)
        XCTAssertTrue(release.asksEdges)
        XCTAssertTrue(release.fullCoverSlip)
        XCTAssertEqual(release.mapping, .rotateLeft)
        XCTAssertFalse(release.mirrored)
        XCTAssertEqual(release.coverSlipName, CoverSlipShape.square.rawValue)
        XCTAssertTrue(release.pausesOnMonitor)
        XCTAssertFalse(release.showsDetections)
        XCTAssertTrue(release.countsOrganisms)
        XCTAssertEqual(release.confidence, 0.5)
        XCTAssertTrue(release.guideDryRun)
    }

    /// One place for the defaults: the release ones are the lab's own except three.
    func testTheReleaseDefaultsDifferFromTheLabsOnlyInMappingCoverageAndTheGuide() {
        var lab = LabSettings()
        lab.mappingName = ScreenMapping.rotateLeft.rawValue
        lab.coverageStep = 1.6
        lab.guideDryRun = true
        XCTAssertEqual(LabSettings.releaseDefaults, lab)
    }

    func testTheGuidedScanIgnoresTheLabsConfidence() {
        var lab = LabSettings()
        lab.confidence = 0.2
        XCTAssertEqual(lab.forGuidedScan(coverage: 1.6).confidence, OrganismDetector.defaultConfidence)
        XCTAssertEqual(OrganismDetector.defaultConfidence, 0.5)
        XCTAssertEqual(OrganismDetector.leastConfidence, Float(0.5))
    }
}
