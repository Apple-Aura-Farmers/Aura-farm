import CoreMedia
import XCTest

@testable import AuraFarm

final class HeatSettingsTests: XCTestCase {
    func testTheUnitsSettingReachesTheDetector() throws {
        XCTAssertEqual(DetectorUnits.neuralEngine.computeUnits, .cpuAndNeuralEngine)
        XCTAssertEqual(DetectorUnits.graphics.computeUnits, .cpuAndGPU)
        XCTAssertEqual(DetectorUnits.neuralEngine.rawValue, "ne")
        XCTAssertEqual(DetectorUnits.graphics.rawValue, "gpu")
        let detector = try OrganismDetector(model: .v2, computeUnits: DetectorUnits.neuralEngine.computeUnits)
        XCTAssertEqual(detector.computeUnits, .cpuAndNeuralEngine)
        XCTAssertEqual(try OrganismDetector().computeUnits, .all, "no arguments is today's V1")
    }

    func testTheLiveCountSessionOpensOnTheNeuralEngineUnlessToldOtherwise() throws {
        let session = LiveCountSession()
        XCTAssertEqual(session.units, .neuralEngine)
        session.prepare()
        let started = Date()
        while session.loadedUnits == nil, Date().timeIntervalSince(started) < 10 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(session.loadedUnits, .cpuAndNeuralEngine)
        session.setUnits(.graphics)
        XCTAssertNil(session.loadedUnits, "reopening")
        let reopened = Date()
        while session.loadedUnits == nil, Date().timeIntervalSince(reopened) < 10 {
            Thread.sleep(forTimeInterval: 0.05)
        }
        XCTAssertEqual(session.loadedUnits, .cpuAndGPU)
    }

    func testTheCameraRatesAnalyseTheSameNominalTenFramesASecond() {
        XCTAssertEqual(CameraRate.fps20.analyzeEveryNthFrame, 2)
        XCTAssertEqual(CameraRate.fps30.analyzeEveryNthFrame, 3)
        XCTAssertEqual(20.0 / Double(CameraRate.fps20.analyzeEveryNthFrame), 10)
        XCTAssertEqual(30.0 / Double(CameraRate.fps30.analyzeEveryNthFrame), 10)
        XCTAssertEqual(CameraRate.fps20.frameDuration, CMTime(value: 1, timescale: 20))
        XCTAssertNil(CameraRate.fps30.frameDuration, "30 fps sets no frame duration")
        XCTAssertEqual(CameraRateThresholds().maxExposureSeconds, 1.0 / 30, accuracy: 1e-12)
    }

    func testThermalStatesHaveNames() {
        XCTAssertEqual(LabDeviceStatus.name(of: .nominal), "nominal")
        XCTAssertEqual(LabDeviceStatus.name(of: .fair), "fair")
        XCTAssertEqual(LabDeviceStatus.name(of: .serious), "serious")
        XCTAssertEqual(LabDeviceStatus.name(of: .critical), "critical")
    }

    func testTheModelTestLabOpensOnV2WithTheCropOn() {
        XCTAssertEqual(ModelTestLabDefaults.model, .v2)
        XCTAssertTrue(ModelTestLabDefaults.cropsToCentre)
        // It no longer reads or writes the old remembered choices.
        UserDefaults.standard.set("v1", forKey: "modelTest.detectorModel")
        UserDefaults.standard.set(false, forKey: "modelTest.cropCentre")
        XCTAssertEqual(ModelTestLabDefaults.model, .v2)
        UserDefaults.standard.removeObject(forKey: "modelTest.detectorModel")
        UserDefaults.standard.removeObject(forKey: "modelTest.cropCentre")
    }
}
