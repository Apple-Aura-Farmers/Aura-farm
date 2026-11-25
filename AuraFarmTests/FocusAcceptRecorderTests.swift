import XCTest

@testable import AuraFarm

final class FocusAcceptRecorderTests: XCTestCase {
    private let frame = SyntheticFrame.make(width: 64, height: 48) { x, y in UInt8((x + y) % 200) }

    private func row(_ seconds: Double) -> FocusAcceptRecord.Row {
        .init(
            t: seconds, state: "turn_one_way", current: 1, peak: 2, level: 0.5, detail: nil,
            active: nil, viewClass: "")
    }

    private func recorder() -> FocusAcceptRecorder {
        let recorder = FocusAcceptRecorder()
        recorder.isOn = true
        addTeardownBlock { recorder.clear() }
        return recorder
    }

    /// Frames every 0.1 s from `from` (exclusive) to `to` (inclusive).
    private func feed(
        _ recorder: FocusAcceptRecorder, from: Double, to: Double, wanted: Bool
    ) {
        var t = from
        while t < to - 1e-9 {
            t += 0.1
            recorder.offer(frame, seconds: t, wanted: wanted, row: wanted ? row(t) : nil)
        }
    }

    private func written(_ recorder: FocusAcceptRecorder) throws -> (FocusAcceptRecord, [URL]) {
        let files = recorder.files
        let json = try XCTUnwrap(files.first { $0.pathExtension == "json" })
        let record = try JSONDecoder().decode(FocusAcceptRecord.self, from: Data(contentsOf: json))
        return (record, files.filter { $0.pathExtension == "png" })
    }

    func testTheFileNamesCarryTheNumberTheWhoTheWhereAndTheSignedSeconds() {
        XCTAssertEqual(
            FocusAcceptRecorder.frameName(1, .person, .setup, offset: -3.5),
            "focus-accept-01-person-setup-t-03.50.png")
        XCTAssertEqual(
            FocusAcceptRecorder.frameName(12, .app, .run, offset: 0.5),
            "focus-accept-12-app-run-t+00.50.png")
    }

    func testTheRingHoldsTheLastTenSecondsAndThreeFramesFollowAlthoughTheStepMovedOn() throws {
        let recorder = recorder()
        let done = expectation(description: "written")
        recorder.onChange = { done.fulfill() }
        feed(recorder, from: 0, to: 30, wanted: true)
        XCTAssertEqual(recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 30), .recorded(1))
        // The step has moved on: nothing is wanted any more, the three frames are still saved.
        feed(recorder, from: 30, to: 31.2, wanted: false)
        wait(for: [done], timeout: 5)
        let (record, pngs) = try written(recorder)
        XCTAssertEqual(pngs.count, 20 + 3)
        XCTAssertEqual(record.frames.count, 23)
        XCTAssertTrue(
            try XCTUnwrap(record.frames.last).hasPrefix("focus-accept-01-person-setup-t+01."))
        XCTAssertEqual(record.where, "setup")
        XCTAssertEqual(record.who, "person")
        XCTAssertTrue(record.readings.allSatisfy { $0.t >= -20 && $0.t <= 0 })
        XCTAssertFalse(record.readings.isEmpty)
    }

    func testReadingsKeepTheLastTwentySecondsOnly() throws {
        let recorder = recorder()
        let done = expectation(description: "written")
        recorder.onChange = { done.fulfill() }
        feed(recorder, from: 0, to: 40, wanted: true)
        recorder.accept(FocusAcceptRecord(), who: .app, place: .run, seconds: 40)
        recorder.flush()
        wait(for: [done], timeout: 5)
        let (record, _) = try written(recorder)
        XCTAssertTrue((195...205).contains(record.readings.count), "\(record.readings.count)")
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(record.readings.first).t, -20.0001)
    }

    func testTheRingIsFreedWhenNothingIsWantedAndNothingIsInProgress() throws {
        let recorder = recorder()
        let done = expectation(description: "written")
        recorder.onChange = { done.fulfill() }
        feed(recorder, from: 0, to: 10, wanted: true)
        feed(recorder, from: 10, to: 11, wanted: false)
        recorder.accept(FocusAcceptRecord(), who: .person, place: .calibrate, seconds: 11)
        recorder.flush()
        wait(for: [done], timeout: 5)
        let (record, pngs) = try written(recorder)
        XCTAssertTrue(pngs.isEmpty, "no ring, no later frame yet: only the readings and the JSON")
        XCTAssertTrue(record.readings.isEmpty)
        XCTAssertEqual(record.where, "calibrate")
    }

    func testAtTwentyRecordsTheTwentyFirstIsRefusedAndClearingStartsAfresh() {
        let recorder = recorder()
        for number in 1...20 {
            XCTAssertEqual(
                recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 1),
                .recorded(number))
        }
        XCTAssertEqual(
            recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 1),
            .limitReached)
        XCTAssertEqual(recorder.count, 20)
        recorder.clear()
        XCTAssertEqual(
            recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 1), .recorded(1))
    }

    func testOffKeepsNothingAndStillLetsTheCallerCarryOn() {
        let recorder = FocusAcceptRecorder()
        feed(recorder, from: 0, to: 5, wanted: true)
        XCTAssertEqual(
            recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 5), .off)
        recorder.flush()
        XCTAssertEqual(recorder.count, 0)
        XCTAssertTrue(recorder.files.isEmpty)

        // Switched off again: what was kept is dropped.
        recorder.isOn = true
        feed(recorder, from: 5, to: 10, wanted: true)
        recorder.isOn = false
        recorder.isOn = true
        let done = expectation(description: "written")
        recorder.onChange = { done.fulfill() }
        recorder.accept(FocusAcceptRecord(), who: .person, place: .setup, seconds: 10)
        recorder.flush()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(recorder.files.filter { $0.pathExtension == "png" }.count, 0)
        recorder.clear()
    }
}
