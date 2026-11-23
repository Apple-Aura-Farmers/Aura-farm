import XCTest

@testable import AuraFarm

/// Performance step 3, part C: the brightness rule, on a fake screen.
final class BrightnessControllerTests: XCTestCase {
    private final class FakeScreen: ScreenBrightness {
        var brightness = 0.5 { didSet { highest = max(highest, brightness) } }
        var highest = 0.5
    }

    private let screen = FakeScreen()
    private lazy var controller = BrightnessController(screen: screen)

    func testItDimsByFifteenPointsFromTheUsersLevel() {
        controller.apply(.coolDown)
        XCTAssertEqual(screen.brightness, 0.35, accuracy: 1e-9)
        controller.apply(.tooHot)
        XCTAssertEqual(screen.brightness, 0.35, accuracy: 1e-9, "the same dim, not deeper")
    }

    func testItNeverGoesUnderTheMinimumNorAboveTheUsersLevel() {
        screen.brightness = 0.3
        controller.apply(.coolDown)
        XCTAssertEqual(screen.brightness, 0.2, accuracy: 1e-9)
        controller.restore()
        screen.brightness = 0.1
        controller.apply(.coolDown)
        XCTAssertEqual(screen.brightness, 0.1, accuracy: 1e-9, "already under the minimum: left alone")
        XCTAssertLessThanOrEqual(screen.highest, 0.5, "never raised above what the user had")
    }

    func testItRestoresWhenTheModeReturnsToNormal() {
        controller.apply(.coolDown)
        controller.apply(.normal)
        XCTAssertEqual(screen.brightness, 0.5, accuracy: 1e-9)
        XCTAssertFalse(controller.isDimmed)
    }

    func testItRestoresOnEveryWayOut() {
        // The scan ends, the page closes, the app resigns, the camera stops: each is `restore()`.
        for _ in 0..<4 {
            screen.brightness = 0.5
            controller.apply(.tooHot)
            XCTAssertEqual(screen.brightness, 0.35, accuracy: 1e-9)
            controller.restore()
            XCTAssertEqual(screen.brightness, 0.5, accuracy: 1e-9)
        }
        controller.restore()
        XCTAssertEqual(screen.brightness, 0.5, accuracy: 1e-9, "restoring twice changes nothing")
    }

    func testAManualChangeBecomesTheUsersLevelAndIsNotFoughtOver() {
        controller.apply(.coolDown)
        screen.brightness = 0.8
        controller.screenChanged()
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 1e-9, "left as the user set it")
        controller.apply(.tooHot)
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 1e-9, "no second dim")
        controller.apply(.normal)
        XCTAssertEqual(screen.brightness, 0.8, accuracy: 1e-9, "their level is the new one")
    }

    func testItsOwnChangeIsNotTakenForTheUsers() {
        controller.apply(.coolDown)
        controller.screenChanged()
        controller.restore()
        XCTAssertEqual(screen.brightness, 0.5, accuracy: 1e-9)
    }

    func testNormalDoesNothing() {
        controller.apply(.normal)
        XCTAssertEqual(screen.brightness, 0.5)
        XCTAssertFalse(controller.isDimmed)
    }
}
