import XCTest

@testable import AuraFarm

/// Phase 2k part D2: when a frame is saved, and the file written.
final class FrameSnapshotTests: XCTestCase {
    func testTheTriggerFiresWhenAnEdgeReasonFirstShowsAndNotWhileItStays() {
        var trigger = SnapshotTrigger()
        func fire(
            _ reason: String, verdict: String = "none", instruction: String = "move",
            line: Bool? = nil
        ) -> Bool {
            trigger.update(
                edgeReason: reason, edgeVerdict: verdict, instruction: instruction,
                lineCandidate: line)
        }
        XCTAssertFalse(fire(""))
        XCTAssertTrue(fire("side_imbalance"))
        XCTAssertFalse(fire("side_imbalance"))
        XCTAssertFalse(fire("spot_hold"), "not one of the listed reasons")
        XCTAssertTrue(fire("corner"))
        XCTAssertTrue(fire("", line: true), "the edge line turns on")
        XCTAssertFalse(fire("", line: nil), "not computed on this frame: still on")
        XCTAssertFalse(fire("", line: true))
        XCTAssertTrue(fire("", instruction: "check_edge"))
        XCTAssertFalse(fire("", instruction: "check_edge"))
        XCTAssertTrue(fire("", verdict: "confirmed"))
    }

    func testTheFileNameCarriesTheCSVSeconds() {
        XCTAssertEqual(FrameSnapshotWriter.fileName(forSeconds: 13.534), "frame-013.53.png")
    }

    func testAutomaticSavesAreOnePerSecondAndManualOnesAreNot() throws {
        let writer = FrameSnapshotWriter()
        writer.begin()
        let buffer = SyntheticFrame.make(width: 64, height: 48) { x, y in UInt8((x * 3 + y) % 256) }
        XCTAssertEqual(writer.save(buffer, csvSeconds: 2.0, automatic: true), "frame-002.00.png")
        XCTAssertNil(writer.save(buffer, csvSeconds: 2.5, automatic: true), "inside the second")
        XCTAssertEqual(writer.save(buffer, csvSeconds: 2.6, automatic: false), "frame-002.60.png")
        XCTAssertEqual(writer.save(buffer, csvSeconds: 3.0, automatic: true), "frame-003.00.png")
        XCTAssertEqual(writer.urls.count, 3)
    }

    func testAFullHDFrameIsAnEightBitGrayscalePNG() throws {
        // Reported: the size of one 1280 x 720 PNG of smooth noise (soil is about as busy).
        let texture = SyntheticFrame.smoothNoise(size: 1280)
        let buffer = SyntheticFrame.make(width: 1280, height: 720) { x, y in
            UInt8(texture[y * 1280 + x])
        }
        let luma = try XCTUnwrap(FrameSnapshotWriter.lumaCopy(of: buffer))
        XCTAssertEqual(luma.data.count, 1280 * 720)
        let url = FileManager.default.temporaryDirectory.appending(path: "snapshot-test.png")
        FrameSnapshotWriter.writePNG(luma, to: url)
        let size = try XCTUnwrap(
            try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        print("PNG bytes for a 1280x720 gray frame: \(size)")
        XCTAssertGreaterThan(size, 1000)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(image.bitsPerComponent, 8)
        XCTAssertEqual(image.width, 1280)
        try? FileManager.default.removeItem(at: url)
    }
}
