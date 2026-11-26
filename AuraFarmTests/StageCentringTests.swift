import XCTest

@testable import AuraFarm

final class StageCentringTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 0)

    func testItCentresOnceOnTheFirstConnectWithAKnownPosition() {
        var centring = StageCentring()
        XCTAssertEqual(centring.connectedTick(positionKnown: false, now: now), .hold)
        XCTAssertEqual(centring.connectedTick(positionKnown: true, now: now), .centre)
        XCTAssertEqual(centring.connectedTick(positionKnown: true, now: now), .hold)
        centring.finish()
        XCTAssertEqual(centring.connectedTick(positionKnown: true, now: now), .carryOn)
    }

    func testAReconnectInTheSameTestDoesNotCentreAgain() {
        var centring = StageCentring()
        _ = centring.connectedTick(positionKnown: true, now: now)
        centring.finish()
        centring.dropped()
        XCTAssertEqual(centring.connectedTick(positionKnown: true, now: now + 60), .carryOn)
    }

    /// `activate()` starts from a fresh value.
    func testANewTestCentresAgain() {
        var centring = StageCentring()
        _ = centring.connectedTick(positionKnown: true, now: now)
        centring.finish()
        centring = StageCentring()
        XCTAssertEqual(centring.connectedTick(positionKnown: true, now: now), .centre)
    }

    func testAnAxisAlreadyAt90IsSkipped() {
        XCTAssertEqual(StageCentring.moves(x: 40, y: 120), [.x, .y])
        XCTAssertEqual(StageCentring.moves(x: 90, y: 120), [.y])
        XCTAssertEqual(StageCentring.moves(x: 40, y: 90), [.x])
        XCTAssertEqual(StageCentring.moves(x: 90, y: 90), [])
    }

    func testAFailedCentringDoesNotBlockTheTest() {
        var centring = StageCentring()
        _ = centring.connectedTick(positionKnown: true, now: now)
        centring.finish()
        XCTAssertFalse(centring.isPending)
    }

    func testABoardThatNeverSaysWhereItIsDoesNotBlockTheTest() {
        var centring = StageCentring()
        let wait = StageCentring.positionWaitSeconds
        XCTAssertEqual(centring.connectedTick(positionKnown: false, now: now), .hold)
        XCTAssertEqual(centring.connectedTick(positionKnown: false, now: now + wait), .noPosition)
        XCTAssertFalse(centring.isPending)
    }

    func testADropBeforeThePositionRestartsTheWait() {
        var centring = StageCentring()
        _ = centring.connectedTick(positionKnown: false, now: now)
        centring.dropped()
        XCTAssertEqual(centring.connectedTick(positionKnown: false, now: now + 60), .hold)
    }
}
