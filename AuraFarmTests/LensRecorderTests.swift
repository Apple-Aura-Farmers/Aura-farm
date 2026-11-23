import AVFoundation
import XCTest

@testable import AuraFarm

final class LensRecorderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(
            path: "lens-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    /// A 1280x720 BGRA frame at `index` of a 20 fps stream.
    private func frame(_ index: Int, fps: Int = 20) throws -> CMSampleBuffer {
        var pixels: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, LensRecorder.width, LensRecorder.height, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixels)
        let buffer = try XCTUnwrap(pixels)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            // A moving grey so the encoder has something to do.
            memset(base, Int32(index * 4 % 256), CVPixelBufferGetDataSize(buffer))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
            presentationTimeStamp: CMTime(value: CMTimeValue(100 + index), timescale: CMTimeScale(fps)),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: nil, imageBuffer: buffer, formatDescription: try XCTUnwrap(format),
            sampleTiming: &timing, sampleBufferOut: &sample)
        return try XCTUnwrap(sample)
    }

    /// Feeds frames at the camera's own pace, 20 a second.
    private func feed(_ recorder: LensRecorder, frames: Int) throws {
        for index in 0..<frames {
            recorder.offer(try frame(index))
            usleep(50_000)
        }
    }

    private func finish(_ recorder: LensRecorder) -> LensRecorder.Result {
        let done = expectation(description: "finished")
        var result: LensRecorder.Result?
        recorder.finish {
            result = $0
            done.fulfill()
        }
        wait(for: [done], timeout: 30)
        return result
            ?? LensRecorder.Result(
                url: recorder.url, duration: 0, framesWritten: 0, videoDrops: 0, failure: "none",
                outOfSpace: false)
    }

    private func frameCount(of url: URL) async throws -> (frames: Int, size: CGSize, seconds: Double) {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var frames = 0
        while let sample = output.copyNextSampleBuffer() {
            frames += CMSampleBufferGetNumSamples(sample)
        }
        let size = try await track.load(.naturalSize)
        let duration = try await asset.load(.duration)
        return (frames, size, duration.seconds)
    }

    func testSixtyFramesAtTwentyFpsMakeAPlayableFileOfTheCamerasSize() async throws {
        let recorder = LensRecorder(url: directory.appending(path: "a.mov"))
        try feed(recorder, frames: 60)
        let result = finish(recorder)
        XCTAssertNil(result.failure)
        XCTAssertEqual(result.framesWritten + result.videoDrops, 60)
        let file = try await frameCount(of: recorder.url)
        XCTAssertEqual(file.size, CGSize(width: 1280, height: 720))
        XCTAssertEqual(file.frames, result.framesWritten)
        XCTAssertEqual(file.seconds, 3, accuracy: 0.3)
        XCTAssertEqual(recorder.originSeconds ?? 0, 5, accuracy: 1e-6)
    }

    func testAFrameTheWriterCannotTakeIsDroppedFromTheVideoOnlyAndTheFeedReturnsAtOnce() throws {
        let held = DispatchQueue(label: "test.held")
        held.suspend()
        let recorder = LensRecorder(url: directory.appending(path: "b.mov"), queue: held)
        let frames = try (0..<10).map { try frame($0) }
        let started = Date()
        for frame in frames { recorder.offer(frame) }
        XCTAssertLessThan(Date().timeIntervalSince(started), 0.5, "the feed never waits for the writer")
        XCTAssertEqual(recorder.pendingFrames, LensRecorder.maxPending)
        XCTAssertEqual(recorder.videoDrops, 10 - LensRecorder.maxPending)
        held.resume()
        let result = finish(recorder)
        XCTAssertEqual(result.framesWritten, LensRecorder.maxPending)
        XCTAssertEqual(result.videoDrops, 10 - LensRecorder.maxPending)
    }

    func testFinishingAPartialSessionGivesAPlayableFileAndFinishingTwiceIsSafe() async throws {
        let recorder = LensRecorder(url: directory.appending(path: "c.mov"))
        try feed(recorder, frames: 7)
        let first = finish(recorder)
        let second = finish(recorder)
        XCTAssertEqual(first, second)
        XCTAssertGreaterThan(first.framesWritten, 0)
        let file = try await frameCount(of: recorder.url)
        XCTAssertEqual(file.frames, first.framesWritten)
        // A frame offered after the end is ignored.
        recorder.offer(try frame(99))
        XCTAssertEqual(recorder.pendingFrames, 0)
    }

    func testARecorderThatSawNoFrameLeavesNoFile() {
        let recorder = LensRecorder(url: directory.appending(path: "d.mov"))
        let result = finish(recorder)
        XCTAssertEqual(result.framesWritten, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recorder.url.path))
    }

    // MARK: The engine's switch

    func testWithTheSwitchOffNothingIsRecorded() {
        let engine = ScanEngine()
        engine.setRecordsLensVideo(false)
        engine.analysisQueue.sync {
            engine.cameraRunning = true
            engine.startLensVideo()
            XCTAssertNil(engine.lensRecorder)
            XCTAssertTrue(engine.lensEvents.isEmpty)
        }
    }

    func testTurningTheSwitchOnStartsOneRecordingOnlyWhileTheCameraRuns() {
        let engine = ScanEngine()
        engine.setRecordsLensVideo(true)
        engine.analysisQueue.sync {
            XCTAssertNil(engine.lensRecorder, "no camera yet")
            engine.cameraRunning = true
            engine.startLensVideo()
            let first = engine.lensRecorder
            XCTAssertNotNil(first)
            engine.startLensVideo()
            XCTAssertTrue(engine.lensRecorder === first, "a second start changes nothing")
            XCTAssertEqual(engine.lensEvents.first?.name, "lens_video_started")
        }
        engine.stop()
        engine.analysisQueue.sync {}
        engine.analysisQueue.sync { XCTAssertNil(engine.lensRecorder) }
    }

    func testTheNoteSaysSavedWithTheSpaceLeftOrWhyItStopped() {
        func result(failure: String? = nil, space: Bool = false) -> LensRecorder.Result {
            LensRecorder.Result(
                url: URL(filePath: "/x.mov"), duration: 3, framesWritten: 60, videoDrops: 0,
                failure: failure, outOfSpace: space)
        }
        XCTAssertEqual(ScanEngine.lensVideoNote(for: nil), "")
        let saved = ScanEngine.lensVideoNote(for: result(), available: 2_300_000_000)
        XCTAssertTrue(saved.hasPrefix("Video saved (") && saved.hasSuffix(" GB available)"), saved)
        XCTAssertEqual(
            ScanEngine.lensVideoNote(for: result(failure: "full", space: true)),
            "Video stopped: the phone is out of space")
        XCTAssertEqual(
            ScanEngine.lensVideoNote(for: result(failure: "boom")), "Video stopped: boom")
    }
}
