#if DEBUG
    import AVFoundation
    import Observation

    /// The slide movement lab's model: the scan engine (`ScanEngine`, which the guided scan page
    /// drives too) plus what only the lab has: test modes, label buttons, marks and distances,
    /// statistics, notes, the setup log export and recorded-video replay. It hooks into the
    /// engine's log (`onLogStarted`, `onRowLogged`, `onLogStopped`) and copies none of its code.
    @Observable
    final class SlideMovementLabModel: ScanEngine {
        private(set) var setupLogURL: URL?
        private(set) var labelSummaries: [LabelStatistics.Summary] = []
        private(set) var label = ""
        private(set) var test = SlideLabTest.free
        private(set) var note = ""

        // Recorded-video mode.
        private(set) var isRunningVideo = false
        private(set) var videoProgress = ""
        private(set) var videoSummary: String?
        private(set) var videoExportURL: URL?

        @ObservationIgnored private let videoQueue = DispatchQueue(label: "slidelab.video")
        @ObservationIgnored private let statsQueue = DispatchQueue(
            label: "slidelab.stats", qos: .utility)
        /// Only the rows that carry a label: what the statistics are computed from. Analysis queue.
        @ObservationIgnored private var labelledRows: [MovementLogRow] = []
        @ObservationIgnored private var lastSummaryAt = -Double.infinity
        /// The least gap between two statistics updates, in seconds.
        @ObservationIgnored private let summaryEverySeconds = 1.0

        override init() {
            super.init()
            onLogStarted = { [weak self] in
                guard let self else { return }
                self.labelledRows = []
                self.lastSummaryAt = -Double.infinity
                DispatchQueue.main.async { self.labelSummaries = [] }
            }
            onRowLogged = { [weak self] row, time in
                guard let self else { return }
                if !self.currentLabel.isEmpty { self.labelledRows.append(row) }
                self.refreshStatistics(at: time)
            }
            onLogStopped = { [weak self] in
                guard let self else { return }
                let labelled = self.labelledRows
                self.statsQueue.async {
                    let final = LabelStatistics.summaries(of: labelled)
                    DispatchQueue.main.async { self.labelSummaries = final }
                }
            }
        }

        /// Writes the setup log (at most the last 2 minutes) to a CSV for sharing.
        func exportSetupLog() {
            analysisQueue.async { [weak self] in
                guard let self, !self.setup.log.isEmpty else { return }
                let url = Self.writeSetupLog(self.setup.log)
                DispatchQueue.main.async { self.setupLogURL = url }
            }
        }

        /// Saves the current frame into the log's frame folder (the "Save frame" button).
        func saveFrame() {
            analysisQueue.async { [weak self] in self?.snapshotRequested = true }
        }

        /// "sample", "blank", "blurry", or "" for none. Written into each logged row.
        func setLabel(_ newLabel: String) {
            label = newLabel
            analysisQueue.async { [weak self] in self?.currentLabel = newLabel }
        }

        /// Which test is being run: written into each row and the file name.
        func setTest(_ newTest: SlideLabTest) {
            test = newTest
            analysisQueue.async { [weak self] in self?.currentTest = newTest }
        }

        func setNote(_ newNote: String) {
            note = newNote
            analysisQueue.async { [weak self] in self?.currentNote = newNote }
        }

        /// - Parameter millimetres: the distance the stage moved, read off its vernier scale.
        func markEnd(millimetres: Double?) {
            var text = "Mark end ✓"
            if readouts.pictureCheck == "confirmed", let truth = readouts.trueOffStartFields {
                text += String(format: " · true %.2f field", truth)
            }
            showToast(text)
            analysisQueue.async { [weak self] in
                self?.pendingMark.place(PendingMark(name: "end", millimetres: millimetres))
            }
        }

        private static func writeSetupLog(_ rows: [SetupLogRow]) -> URL? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "slide-movement-setup-\(formatter.string(from: .now)).csv")
            do {
                try SetupLog.csv(rows).write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
            }
        }

        /// Computes the label statistics off the analysis queue, from a copy of the labelled
        /// rows, at most once a second.
        private func refreshStatistics(at time: Double) {
            guard time - lastSummaryAt >= summaryEverySeconds, !labelledRows.isEmpty else { return }
            lastSummaryAt = time
            let labelled = labelledRows
            statsQueue.async { [weak self] in
                let summaries = LabelStatistics.summaries(of: labelled)
                DispatchQueue.main.async {
                    guard let self, self.labelSummaries != summaries else { return }
                    self.labelSummaries = summaries
                }
            }
        }

        // MARK: Recorded video

        /// Runs the same chain over a recorded video, reading frames the way
        /// `VideoSweepRunner` does: every third frame, the camera's pixel format. Every
        /// analyzed frame is logged, timed by the video's presentation time. Labels and marks
        /// do not apply.
        func runVideo(url: URL, startSeconds: Double) {
            guard !isRunningVideo else { return }
            isRunningVideo = true
            videoSummary = nil
            videoExportURL = nil
            videoProgress = "Opening…"

            videoQueue.async { [weak self] in
                guard let self else { return }
                let outcome = self.readVideo(url: url, startSeconds: startSeconds)
                DispatchQueue.main.async {
                    self.isRunningVideo = false
                    self.videoSummary = outcome.summary
                    self.videoExportURL = outcome.csv
                }
            }
        }

        private func readVideo(url: URL, startSeconds: Double) -> (summary: String, csv: URL?) {
            let asset = AVURLAsset(url: url)
            guard let track = try? Self.firstVideoTrack(of: asset),
                let reader = try? AVAssetReader(asset: asset)
            else { return ("The video could not be opened.", nil) }

            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
                ])
            guard reader.canAdd(output) else { return ("The video could not be read.", nil) }
            reader.add(output)
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: max(startSeconds, 0), preferredTimescale: 600),
                duration: CMTime(seconds: VideoSweepRunner.maxSecondsRead, preferredTimescale: 600))
            guard reader.startReading() else { return ("The video could not be read.", nil) }

            let pipeline = SlideMovementPipeline()
            pipeline.fieldMode = fieldRegion
            let measureAgreement = measuresHopAgreement
            var logged: [MovementLogRow] = []
            var origin: Double?
            var frameNumber = 0
            var last: SlideMovementStep?
            var videoIndicators = MovementIndicators()
            // About 10 analysed frames a second whatever the video's rate (the capture flow's own
            // `VideoSweepRunner.analyzeEveryNthFrame` is not changed).
            let videoStride = max(1, Int((Double(track.nominalFrameRate) / 10).rounded()))

            while true {
                let finished: Bool = autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return true }
                    frameNumber += 1
                    guard frameNumber % videoStride == 0,
                        let buffer = CMSampleBufferGetImageBuffer(sample)
                    else { return false }
                    let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
                    let start = origin ?? time
                    origin = start
                    guard
                        let step = pipeline.process(
                            buffer, seconds: time, measureAgreement: measureAgreement)
                    else { return false }
                    last = step
                    videoIndicators.update(
                        shake: step.shake, anchorOffset: step.usedOffset,
                        positionFields: step.positionFields, isLost: step.isLost,
                        event: step.event, referenceSide: step.boxSide, seconds: time,
                        hopDistance: step.hopLimit, hasDetail: step.hasDetail)
                    logged.append(
                        row(
                            from: step, indicators: videoIndicators, seconds: time - start,
                            label: "", mark: "", millimetres: nil, test: .free, note: ""))
                    if logged.count % 10 == 0 {
                        let text = "\(logged.count) frames, \(step.hops) hops"
                        DispatchQueue.main.async { self.videoProgress = text }
                    }
                    return false
                }
                if finished { break }
            }
            reader.cancelReading()

            guard let last else { return ("No frame could be analyzed.", nil) }
            let x = String(format: "%.2f", Double(last.positionFields.x))
            let y = String(format: "%.2f", Double(last.positionFields.y))
            let summary =
                "\(logged.count) frames analyzed, \(last.hops) hops, \(last.gaps) gaps. "
                + "Final position (\(x), \(y)) fields."
            return (summary, Self.write(logged, test: .free))
        }

        /// AVFoundation's track loading is async; this runs on a queue of its own already.
        private static func firstVideoTrack(of asset: AVAsset) throws -> AVAssetTrack? {
            let semaphore = DispatchSemaphore(value: 0)
            var found: AVAssetTrack?
            var failure: Error?
            Task {
                do { found = try await asset.loadTracks(withMediaType: .video).first } catch {
                    failure = error
                }
                semaphore.signal()
            }
            semaphore.wait()
            if let failure { throw failure }
            return found
        }
    }
#endif
