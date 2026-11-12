#if DEBUG
    import AVFoundation
    import Observation

    /// The camera and the recorded-video runner behind the slide movement lab. It follows
    /// `CaptureViewModel`'s patterns (session queue, analysis queue, every third frame, 720p,
    /// locked focus, 420f frames) and is a model of its own so the capture screen is left
    /// alone. Frames are analyzed off the main thread; UI state is only changed on the main
    /// queue.
    ///
    /// Debug builds only. Measurement tooling: nothing here is saved to `FrameSets`; the CSV
    /// goes to a temporary file for sharing.
    @Observable
    final class SlideMovementLabModel: NSObject {
        // MARK: UI state (main queue only)

        private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
        // Published in pieces, so each small view reads only what it shows.
        private(set) var statusInfo = SlideMovementInfo.Status()
        private(set) var readouts = SlideMovementInfo.Readouts()
        private(set) var trailInfo = SlideMovementInfo.Trail()
        private(set) var fieldInfo = SlideMovementInfo.Field()
        /// The guide dry run's block (see `GuideDryRun`).
        private(set) var guideInfo = SlideMovementInfo.Guide()
        private(set) var guideDryRun = false
        /// The "What the app sees" picture, when it is switched on.
        private(set) var thumbnailImage: CGImage?
        private(set) var showsThumbnail = false
        private(set) var labelSummaries: [LabelStatistics.Summary] = []
        private(set) var fieldRegion = FieldRegionMode.auto
        private(set) var measuresHopAgreement = false
        /// A brief confirmation after Mark start or Mark end ("Mark start ✓").
        private(set) var markToast: String?
        @ObservationIgnored private var toastTask: Task<Void, Never>?
        private(set) var cameraError: String?
        private(set) var lensPosition = CaptureViewModel.defaultLensPosition
        private(set) var label = ""
        private(set) var test = SlideLabTest.free
        private(set) var note = ""
        private(set) var isLogging = false
        /// False while the person is setting the phone up: the camera runs so they can position
        /// and focus it, but nothing is analyzed until they tap Start.
        private(set) var isAnalyzing = false
        private(set) var rowCount = 0
        /// The CSV of the last log that was stopped with rows in it.
        private(set) var exportURL: URL?

        // Recorded-video mode.
        private(set) var isRunningVideo = false
        private(set) var videoProgress = ""
        private(set) var videoSummary: String?
        private(set) var videoExportURL: URL?

        // MARK: Camera

        @ObservationIgnored let session = AVCaptureSession()
        @ObservationIgnored private let sessionQueue = DispatchQueue(label: "slidelab.session")
        @ObservationIgnored private let analysisQueue = DispatchQueue(label: "slidelab.analysis")
        @ObservationIgnored private let videoQueue = DispatchQueue(label: "slidelab.video")
        @ObservationIgnored private let statsQueue = DispatchQueue(
            label: "slidelab.stats", qos: .utility)
        @ObservationIgnored private var isConfigured = false
        @ObservationIgnored private var device: AVCaptureDevice?

        // MARK: Analysis (analysis queue only)

        @ObservationIgnored private var pipeline: SlideMovementPipeline = {
            let pipeline = SlideMovementPipeline()
            pipeline.requiresReview = true
            return pipeline
        }()
        @ObservationIgnored private let dryRun = GuideDryRun()
        @ObservationIgnored private var guideEnabled = false
        @ObservationIgnored private var latestGuide: GuideRowFields?
        @ObservationIgnored private var latestGuideInfo = SlideMovementInfo.Guide()
        @ObservationIgnored private var frameCount = 0
        @ObservationIgnored private var analyzing = false
        /// Analyze every Nth frame: about 10 fps at 30 fps capture.
        @ObservationIgnored private let analyzeEveryNthFrame = 3
        @ObservationIgnored private var logging = false
        @ObservationIgnored private var rows: [MovementLogRow] = []
        @ObservationIgnored private var logOrigin: Double?
        @ObservationIgnored private var currentLabel = ""
        @ObservationIgnored private var pendingMark = MarkSlot()
        @ObservationIgnored private var trailBlind: [Bool] = []
        @ObservationIgnored private var trail: [CGPoint] = []
        @ObservationIgnored private var lastEventName = ""
        @ObservationIgnored private var indicators = MovementIndicators()
        @ObservationIgnored private var currentTest = SlideLabTest.free
        @ObservationIgnored private var currentNote = ""
        @ObservationIgnored private var latestPositionFields = CGPoint.zero
        @ObservationIgnored private var startTrailPoint: CGPoint?
        @ObservationIgnored private var hopPoints: [CGPoint] = []
        @ObservationIgnored private var lostPoints: [CGPoint] = []
        @ObservationIgnored private var hopCount = 0
        @ObservationIgnored private var lostCount = 0
        /// Only the rows that carry a label: what the statistics are computed from.
        @ObservationIgnored private var labelledRows: [MovementLogRow] = []
        @ObservationIgnored private var lastSummaryAt = -Double.infinity
        /// The least gap between two statistics updates, in seconds.
        @ObservationIgnored private let summaryEverySeconds = 1.0
        /// About 6 seconds of trail at 10 fps.
        @ObservationIgnored private let trailLength = 60
        @ObservationIgnored private var lastPublishAt = -Double.infinity
        /// The least gap between two publishes to the screen, in seconds. PLACEHOLDER: not
        /// calibrated; 6 a second keeps a Debug build's drawing from eating the analysis.
        @ObservationIgnored private let publishEverySeconds = 1.0 / 6
        @ObservationIgnored private var measureAgreementEnabled = false

        // MARK: Lifecycle

        func start() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                authorization = .authorized
                runSession()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self else { return }
                        self.authorization = granted ? .authorized : .denied
                        if granted { self.runSession() }
                    }
                }
            default:
                authorization = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }

        /// Leaves set-up: clears the old tracking, and starts learning the eyepiece mask afresh
        /// from the next frame.
        func beginAnalysis() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.pipeline.redetectField()
                self.clearTrackingDisplay()
                self.analyzing = true
                DispatchQueue.main.async { self.isAnalyzing = true }
            }
        }

        /// Back to set-up: the camera keeps running, analysis pauses and any log is ended.
        func endAnalysis() {
            stopLog()
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.analyzing = false
                DispatchQueue.main.async { self.isAnalyzing = false }
            }
        }

        func stop() {
            endAnalysis()
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        /// Moves the lens. There is no autofocus: it hunts on a microscope.
        func setLensPosition(_ position: Float) {
            let clamped = min(max(position, 0), 1)
            sessionQueue.async { [weak self] in
                guard let self, let device = self.device, device.isFocusModeSupported(.locked),
                    (try? device.lockForConfiguration()) != nil
                else { return }
                device.setFocusModeLocked(lensPosition: clamped, completionHandler: nil)
                device.unlockForConfiguration()
                DispatchQueue.main.async { self.lensPosition = clamped }
            }
        }

        // MARK: Controls

        /// Back to zero, anchoring afresh on the next frame.
        func resetPosition() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.pipeline.resetPosition()
                self.dryRun.reset()
                self.latestGuide = nil
                self.clearTrackingDisplay()
            }
        }

        /// Forgets the learned eyepiece mask and learns it again. Use after moving the phone
        /// or changing the light.
        func redetectField() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.pipeline.redetectField()
                self.clearTrackingDisplay()
            }
        }

        /// The person confirmed the learned field: tracking starts.
        func confirmField() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.pipeline.confirmField()
                self.clearTrackingDisplay()
            }
        }

        /// The person drew the field by hand (still waiting for their confirmation).
        func adjustField(to circle: FieldCircle) {
            analysisQueue.async { [weak self] in self?.pipeline.adjustField(to: circle) }
        }

        private func clearTrackingDisplay() {
            trail = []
            trailBlind = []
            lastPublishAt = -Double.infinity
            lastEventName = ""
            indicators.clearStart()
            startTrailPoint = nil
            hopPoints = []
            lostPoints = []
            latestPositionFields = .zero
        }

        func startLog() {
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.rows = []
                self.logOrigin = nil
                self.pendingMark.clear()
                self.labelledRows = []
                self.lastSummaryAt = -Double.infinity
                self.logging = true
                DispatchQueue.main.async {
                    self.labelSummaries = []
                    self.isLogging = true
                    self.rowCount = 0
                    self.exportURL = nil
                }
            }
        }

        /// Ends the log and writes its CSV to a temporary file for sharing.
        func stopLog() {
            analysisQueue.async { [weak self] in
                guard let self, self.logging else { return }
                self.logging = false
                let url = Self.write(self.rows, test: self.currentTest)
                let count = self.rows.count
                let labelled = self.labelledRows
                self.statsQueue.async {
                    let final = LabelStatistics.summaries(of: labelled)
                    DispatchQueue.main.async { self.labelSummaries = final }
                }
                DispatchQueue.main.async {
                    self.isLogging = false
                    self.rowCount = count
                    self.exportURL = url
                }
            }
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

        /// Where movement is registered; see `FieldRegionMode`.
        func setFieldRegion(_ mode: FieldRegionMode) {
            fieldRegion = mode
            analysisQueue.async { [weak self] in self?.pipeline.fieldMode = mode }
        }

        /// Whether a hop is checked against `PanoramaStitcher.agreement`. Off by default: it
        /// costs two image conversions and a correlation.
        /// Switches the "What the app sees" picture on or off.
        func setShowsThumbnail(_ shown: Bool) {
            showsThumbnail = shown
            if !shown { thumbnailImage = nil }
            analysisQueue.async { [weak self] in self?.pipeline.makesThumbnail = shown }
        }

        /// Switches the guide dry run on or off; either way it starts afresh.
        func setGuideDryRun(_ enabled: Bool) {
            guideDryRun = enabled
            if !enabled { guideInfo = SlideMovementInfo.Guide() }
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.guideEnabled = enabled
                self.dryRun.reset()
                self.latestGuide = nil
                self.latestGuideInfo = SlideMovementInfo.Guide()
            }
        }

        /// How the frame's axes map onto the screen, which the guide works in.
        func setScreenMapping(_ mapping: ScreenMapping, mirrored: Bool) {
            analysisQueue.async { [weak self] in
                self?.dryRun.mapping = mapping
                self?.dryRun.mirrored = mirrored
            }
        }

        func setMeasuresHopAgreement(_ enabled: Bool) {
            measuresHopAgreement = enabled
            analysisQueue.async { [weak self] in self?.measureAgreementEnabled = enabled }
        }

        /// Marks the start in the CSV, and the spot the "off start" distance is measured from.
        func markStart() {
            showToast("Mark start ✓")
            analysisQueue.async { [weak self] in
                guard let self else { return }
                self.pendingMark.place(PendingMark(name: "start", millimetres: nil))
                self.pipeline.setStartPicture()
                self.indicators.markStart(at: self.latestPositionFields)
                self.startTrailPoint = self.latestPositionFields
            }
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

        /// Confirms a mark on screen for a moment. A mark made while no log is running is not
        /// written anywhere, and the toast says so. Main queue only.
        private func showToast(_ text: String) {
            markToast = isLogging ? text : "\(text) (not logging)"
            toastTask?.cancel()
            toastTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                self?.markToast = nil
            }
        }

        // MARK: Session

        private func runSession() {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                if !self.isConfigured { self.configureSession() }
                guard self.isConfigured else { return }
                // Every visit starts at set-up; tapping Start learns the eyepiece mask afresh.
                self.analysisQueue.async {
                    self.analyzing = false
                    self.frameCount = 0
                    DispatchQueue.main.async { self.isAnalyzing = false }
                }
                if !self.session.isRunning { self.session.startRunning() }
            }
        }

        private func configureSession() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }

            session.sessionPreset = .hd1280x720

            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                publishError("The camera could not be opened.")
                return
            }
            session.addInput(input)
            self.device = device

            // Fixed focus: autofocus hunts on a microscope. The user moves the lens by hand.
            if device.isFocusModeSupported(.locked), (try? device.lockForConfiguration()) != nil {
                device.setFocusModeLocked(
                    lensPosition: CaptureViewModel.defaultLensPosition, completionHandler: nil)
                device.unlockForConfiguration()
            }

            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: analysisQueue)

            guard session.canAddOutput(output) else {
                publishError("The camera output could not be set up.")
                return
            }
            session.addOutput(output)
            isConfigured = true
        }

        private func publishError(_ message: String) {
            DispatchQueue.main.async { [weak self] in self?.cameraError = message }
        }

        // MARK: Row building

        private func row(
            from step: SlideMovementStep, indicators: MovementIndicators, seconds: Double,
            label: String, mark: String, millimetres: Double?, test: SlideLabTest, note: String,
            guide: GuideRowFields? = nil
        ) -> MovementLogRow {
            MovementLogRow(
                seconds: seconds,
                brightness: step.stats.brightness, sharpness: step.stats.sharpness,
                contrast: step.stats.contrast,
                shakeX: step.shake.map { Double($0.x) }, shakeY: step.shake.map { Double($0.y) },
                anchorX: step.anchorOffset.map { Double($0.x) },
                anchorY: step.anchorOffset.map { Double($0.y) },
                positionX: Double(step.position.x), positionY: Double(step.position.y),
                positionXFrames: Double(step.positionFrames.x),
                positionYFrames: Double(step.positionFrames.y),
                hops: step.hops, gaps: step.gaps, isLost: step.isLost,
                event: step.eventName, hopAgreement: step.hopAgreement,
                label: label, mark: mark, markMillimetres: millimetres,
                frameWidth: Int(step.frameSize.width), frameHeight: Int(step.frameSize.height),
                test: test.fileSlug, note: note, speedFraction: indicators.speedFraction,
                status: indicators.status.csvName, hopProgress: indicators.hopProgress,
                stillSeconds: indicators.stillSeconds, offStartFields: indicators.offStartFields,
                fieldRegion: step.fieldRegionName,
                analysisMilliseconds: step.analysisMilliseconds, analyzedFps: step.analyzedFps,
                fieldOpenShare: step.fieldState?.openShare, boxSidePx: step.boxSide,
                positionXFields: Double(step.positionFields.x),
                positionYFields: Double(step.positionFields.y), hopLimitPx: step.hopLimit,
                boxBrightness: step.boxStats.brightness, boxSharpness: step.boxStats.sharpness,
                boxContrast: step.boxStats.contrast, reading: step.reading,
                predictedStreak: step.predictedStreak, noDetail: !step.hasDetail,
                blindStretches: step.blindStretches,
                startMatchX: step.startMatch.map { Double($0.x) },
                startMatchY: step.startMatch.map { Double($0.y) },
                trueOffStartFields: step.trueOffStartFields,
                trackerErrorFields: step.trackerErrorFields,
                blankReturnsMatched: step.blankReturnsMatched,
                blankReturnsUnmatched: step.blankReturnsUnmatched,
                blankReturn: step.blankReturnEvent, viewClass: guide?.viewClass ?? "",
                guideState: guide?.state ?? "", guideInstruction: guide?.instruction ?? "",
                guideTargetDx: guide?.targetDx, guideTargetDy: guide?.targetDy,
                guideCaptures: guide?.captures)
        }

        private static func write(_ rows: [MovementLogRow], test: SlideLabTest) -> URL? {
            guard !rows.isEmpty else { return nil }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let url = FileManager.default.temporaryDirectory
                .appending(path: "slide-movement-\(test.fileSlug)-\(formatter.string(from: .now)).csv")
            do {
                try MovementLog.csv(rows).write(to: url, atomically: true, encoding: .utf8)
                return url
            } catch {
                return nil
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

            while true {
                let finished: Bool = autoreleasepool {
                    guard let sample = output.copyNextSampleBuffer() else { return true }
                    frameNumber += 1
                    guard frameNumber % VideoSweepRunner.analyzeEveryNthFrame == 0,
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

    // MARK: - Frame analysis

    extension SlideMovementLabModel: AVCaptureVideoDataOutputSampleBufferDelegate {
        func captureOutput(
            _ output: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            frameCount += 1
            guard analyzing, frameCount % analyzeEveryNthFrame == 0,
                let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            guard
                let step = pipeline.process(
                    buffer, seconds: time, measureAgreement: logging && measureAgreementEnabled)
            else { return }

            if let image = step.thumbnail {
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.showsThumbnail else { return }
                    self.thumbnailImage = image
                }
            }
            latestPositionFields = step.positionFields
            indicators.update(
                shake: step.shake, anchorOffset: step.usedOffset,
                positionFields: step.positionFields, isLost: step.isLost, event: step.event,
                referenceSide: step.boxSide, seconds: time, hopDistance: step.hopLimit,
                hasDetail: step.hasDetail)
            if guideEnabled {
                let result = dryRun.update(step: step, indicators: indicators, seconds: time)
                latestGuide = result.fields
                latestGuideInfo = result.info
            }
            if step.event == .hop {
                hopCount += 1
                hopPoints.append(step.positionFields)
                if hopPoints.count > 300 { hopPoints.removeFirst() }
            }
            if step.event == .lost {
                lostCount += 1
                lostPoints.append(step.positionFields)
                if lostPoints.count > 100 { lostPoints.removeFirst() }
            }
            if step.event != .none { lastEventName = step.eventName }

            trail.append(step.positionFields)
            trailBlind.append(!step.hasDetail)
            if trail.count > trailLength {
                trail.removeFirst(trail.count - trailLength)
                trailBlind.removeFirst(trailBlind.count - trailLength)
            }

            if logging {
                let origin = logOrigin ?? time
                logOrigin = origin
                let mark = pendingMark.take()
                let logged = row(
                    from: step, indicators: indicators, seconds: time - origin,
                    label: currentLabel, mark: mark?.name ?? "",
                    millimetres: mark?.millimetres, test: currentTest, note: currentNote,
                    guide: guideEnabled ? latestGuide : nil)
                rows.append(logged)
                if !currentLabel.isEmpty { labelledRows.append(logged) }
                refreshStatistics(at: time)
            }

            guard time - lastPublishAt >= publishEverySeconds else { return }
            lastPublishAt = time
            publish(step, time: time)
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

        /// Hands the screen the latest values, each piece only when it changed.
        private func publish(_ step: SlideMovementStep, time: Double) {
            let status = SlideMovementInfo.Status(
                status: indicators.status, speedFraction: indicators.speedFraction)
            let readouts = SlideMovementInfo.Readouts(
                stats: step.stats, position: step.position,
                positionFrames: step.positionFrames, positionFields: step.positionFields,
                boxSide: step.boxSide, hopLimit: step.hopLimit, hops: step.hops, gaps: step.gaps,
                lastEvent: lastEventName, frameSize: step.frameSize,
                stillSeconds: indicators.stillSeconds, offStartFields: indicators.offStartFields,
                isHome: indicators.isHome,
                elapsedLogSeconds: logging ? time - (logOrigin ?? time) : 0, hopCount: hopCount,
                lostCount: lostCount, analysisMilliseconds: step.analysisMilliseconds,
                analyzedFps: step.analyzedFps, boxStats: step.boxStats, reading: step.reading,
                hasDetail: step.hasDetail, blindStretches: step.blindStretches,
                pictureCheck: step.pictureCheck, trueOffStartFields: step.trueOffStartFields,
                trackerErrorFields: step.trackerErrorFields)
            let guideInfo = guideEnabled ? latestGuideInfo : SlideMovementInfo.Guide()
            let trailInfo = SlideMovementInfo.Trail(
                trail: trail, hopPoints: hopPoints, lostPoints: lostPoints,
                startPoint: startTrailPoint, hopProgress: indicators.hopProgress,
                hopCount: hopCount, blind: trailBlind)
            let circle =
                step.awaitingReview ? step.fieldState?.mask.flatMap { FieldCircle(fitting: $0) } : nil
            let fieldInfo = SlideMovementInfo.Field(
                state: step.fieldState,
                registrationRect: step.registrationRect, frameSize: step.frameSize,
                awaitingReview: step.awaitingReview, circle: circle)
            let count = rows.count
            let isLogging = logging
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.statusInfo != status { self.statusInfo = status }
                if self.readouts != readouts { self.readouts = readouts }
                if self.trailInfo != trailInfo { self.trailInfo = trailInfo }
                if self.fieldInfo != fieldInfo { self.fieldInfo = fieldInfo }
                if self.guideInfo != guideInfo { self.guideInfo = guideInfo }
                if isLogging, self.rowCount != count { self.rowCount = count }
            }
        }
    }
#endif
