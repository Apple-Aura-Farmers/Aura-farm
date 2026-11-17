#if DEBUG
    import CoreGraphics
    import CoreML
    import CoreVideo
    import Foundation
    import QuartzCore

    /// What counting did on one frame, for the CSV.
    struct LiveCountFrameLog: Equatable {
        var active = false
        var ran = false
        var skipReason = ""
        var milliseconds: Double?
        var found: Int?
        var outside: Int?
        var newInTally: Int?
        var newOnMap: Int?
        var repeatOnMap: Int?
        var tallyTotal: Int?
        var mapTotal: Int?
        /// Boxes the guards dropped on this frame: the eyepiece disc, and too big for the input.
        var droppedDisc: Int?
        var droppedBig: Int?
        var model = ""
        var units = ""
        /// "Volvox id=7 slide=(12,-40) column=2", one per organism counted on this frame.
        var counted: [String] = []
    }

    /// Runs the detector on the frames the guide's counting rules let through and feeds
    /// `LiveOrganismCounter`. Analysis queue only, except `prepare()`, which any queue may call.
    ///
    /// The detector opens off the analysis queue (`prepare()`, at Mark start and when the model
    /// changes), on the CPU and GPU (measured 5.1 ms a frame on an iPhone 17 in
    /// `CaptureViewModel`). Until it is ready, frames are skipped as "model_loading".
    final class LiveCountSession {
        /// Settings, set from the lab's switches (through the analysis queue).
        var isEnabled = true
        /// On by default: V2 calls the whole bright eyepiece disc Volvox or Nematode without it.
        var cropsToEyepiece = true
        var minimumConfidence = OrganismDetector.leastConfidence
        /// Which model counts. Change it with `setModel` only.
        private(set) var model = DetectorModel.v2
        /// The hardware it runs on: the Neural Engine by default, for power per inference. Change
        /// it with `setUnits` only.
        private(set) var units = DetectorUnits.neuralEngine

        private let loadQueue = DispatchQueue(label: "slidelab.detector-load", qos: .userInitiated)
        /// Guards the properties below: the load finishes on `loadQueue`. `generation` counts the
        /// changes of model or units, so a load that finishes after one is thrown away.
        private let lock = NSLock()
        private var loaded: OrganismDetector?
        private var loadingGeneration: Int?
        private var generation = 0
        private var wanted = (model: DetectorModel.v2, units: DetectorUnits.neuralEngine)
        private var loadFailure: String?
        private var loadMilliseconds: Double?
        /// When the detector last ran, on the run's clock.
        private var lastDetectedAt: Double?

        /// If the analysis p95 goes above this, only every second eligible frame is detected.
        /// PLACEHOLDER: about 80% of the 100 ms between analysed frames at 10 fps.
        static let slowAnalysisMilliseconds = 80.0
        private static let windowFrames = 60

        private(set) var counter = LiveOrganismCounter()
        private let snapshots = DetectionSnapshotWriter()
        private var runsEverySecond = false
        private var eligibleSeen = 0
        private var recentMilliseconds: [Double] = []
        private var hapticCount = 0
        private var lastHapticAt = -Double.infinity
        private var lastCircle: FieldCircle?

        /// A new run: counts, snapshots and timing start afresh. The model stays open.
        func begin(stamp: String) {
            counter.reset()
            snapshots.begin(stamp: stamp)
            runsEverySecond = false
            eligibleSeen = 0
            recentMilliseconds = []
            hapticCount = 0
            lastDetectedAt = nil
        }

        /// How long ago the detector last ran, on the run's clock; nil if it has not.
        func secondsSinceDetection(at seconds: Double) -> Double? {
            lastDetectedAt.map { seconds - $0 }
        }

        /// The hardware the open detector was opened for; nil until it is open.
        var loadedUnits: MLComputeUnits? {
            lock.lock()
            defer { lock.unlock() }
            return loaded?.computeUnits
        }

        var framesDetected: Int { counter.framesCounted }
        /// What counted, for the run record: the class names are the model's, without background.
        var detectorOptions: (confidence: Float, crop: Bool, classes: [String]) {
            lock.lock()
            let names = loaded?.classNames
            lock.unlock()
            let all = names ?? (model == .v1 ? OrganismDetector.classNames : DetectorModel.v2ClassNames)
            return (minimumConfidence, cropsToEyepiece, Array(all.dropFirst()))
        }

        // MARK: Opening the model

        /// Switches model: the live count starts afresh and the new model opens in the background.
        func setModel(_ newModel: DetectorModel) {
            guard newModel != model else { return }
            model = newModel
            reopen()
        }

        /// Switches the hardware: the detector reopens in the background and the live count starts
        /// afresh (it is locked during a run, so this never changes a count half way).
        func setUnits(_ newUnits: DetectorUnits) {
            guard newUnits != units else { return }
            units = newUnits
            reopen()
        }

        private func reopen() {
            counter.reset()
            recentMilliseconds = []
            eligibleSeen = 0
            runsEverySecond = false
            lastDetectedAt = nil
            lock.lock()
            generation += 1
            wanted = (model, units)
            loaded = nil
            loadFailure = nil
            loadMilliseconds = nil
            lock.unlock()
            prepare()
        }

        /// Opens the chosen model on a queue of its own, unless it is open or opening. Called at
        /// Mark start and when the guide starts, so there is no stall at column 1's first spot.
        func prepare() {
            lock.lock()
            let wanted = wanted
            let ticket = generation
            let skip = loaded != nil || loadingGeneration == ticket || loadFailure != nil
            if !skip { loadingGeneration = ticket }
            lock.unlock()
            guard !skip else { return }
            loadQueue.async { [weak self] in
                let started = CACurrentMediaTime()
                var opened: OrganismDetector?
                var failure: String?
                do {
                    opened = try OrganismDetector(
                        model: wanted.model, computeUnits: wanted.units.computeUnits)
                } catch {
                    failure = error.localizedDescription
                }
                let took = (CACurrentMediaTime() - started) * 1000
                print(
                    "LIVECOUNT opened \(wanted.model.resourceName) on \(wanted.units.rawValue) in \(Int(took)) ms"
                )
                guard let self else { return }
                self.lock.lock()
                if self.loadingGeneration == ticket { self.loadingGeneration = nil }
                // A model or units changed meanwhile: this is not the one wanted any more.
                if self.generation == ticket {
                    self.loaded = opened
                    self.loadFailure = failure
                    self.loadMilliseconds = failure == nil ? took : nil
                }
                self.lock.unlock()
            }
        }

        private func readyDetector() -> OrganismDetector? {
            lock.lock()
            defer { lock.unlock() }
            return loaded
        }

        /// The p50 and p95 of the analysis time (tracker plus detector) over the last frames.
        var analysisPercentiles: (p50: Double, p95: Double)? {
            guard recentMilliseconds.count >= 10 else { return nil }
            let sorted = recentMilliseconds.sorted()
            return (sorted[sorted.count / 2], sorted[min(sorted.count - 1, sorted.count * 95 / 100)])
        }

        /// One analysed frame while counting is on (the guide's `countingActive`).
        /// - Parameters:
        ///   - skipReason: why this frame may not go to the detector (see
        ///     `LiveOrganismCounter.skipReason`), nil when it may.
        ///   - trackerPosition: `SlideMovementStep.position`, px.
        func process(
            buffer: CVPixelBuffer, skipReason: String?, pictureMoved: CGPoint,
            trackerPosition: CGPoint, frameSize: CGSize, fieldCircle: FieldCircle?, seconds: Double,
            column: Int, trackerMilliseconds: Double
        ) -> LiveCountFrameLog {
            var log = LiveCountFrameLog(active: true)
            if let fieldCircle { lastCircle = fieldCircle }
            guard isEnabled else {
                log.skipReason = "off"
                note(trackerMilliseconds)
                return log
            }
            var reason = skipReason
            if reason == nil {
                eligibleSeen += 1
                if runsEverySecond, eligibleSeen % 2 == 0 { reason = "stride" }
            }
            if let reason {
                counter.skip(pictureMoved: pictureMoved, reason: reason)
                log.skipReason = reason
                finish(&log)
                note(trackerMilliseconds)
                return log
            }
            guard var detector = readyDetector() else {
                prepare()
                lock.lock()
                let failed = loadFailure != nil
                lock.unlock()
                let why = failed ? "no_model" : "model_loading"
                counter.skip(pictureMoved: pictureMoved, reason: why)
                log.skipReason = why
                finish(&log)
                note(trackerMilliseconds)
                return log
            }
            detector.minimumConfidence = minimumConfidence
            var crop: CGRect?
            if cropsToEyepiece, let circle = lastCircle {
                crop = FieldCentring.cropRect(for: circle, frameSize: frameSize)
            }
            let started = CACurrentMediaTime()
            let detections = (try? detector.detections(in: buffer, crop: crop)) ?? []
            let milliseconds = (CACurrentMediaTime() - started) * 1000
            let result = counter.update(
                detections: detections, pictureMoved: pictureMoved, trackerPosition: trackerPosition,
                frameSize: frameSize, fieldCircle: fieldCircle ?? lastCircle, crop: crop,
                seconds: seconds, column: column)
            lastDetectedAt = seconds
            log.ran = true
            log.milliseconds = milliseconds
            log.found = result.found
            log.outside = result.outsideField
            log.newInTally = result.newInTally
            log.newOnMap = result.newOnMap
            log.repeatOnMap = result.repeatOnMap
            log.droppedDisc = result.droppedDisc
            log.droppedBig = result.droppedBig
            for entry in result.newEntries {
                log.counted.append(
                    "\(entry.label) id=\(entry.id) slide=(\(Int(entry.position.x)),\(Int(entry.position.y))) column=\(entry.column)"
                )
            }
            if !result.newEntries.isEmpty {
                if seconds - lastHapticAt >= 0.5 {
                    lastHapticAt = seconds
                    hapticCount += 1
                }
                let drawn = counter.visibleBoxes.filter { $0.status == .counted }.map {
                    (id: $0.id, label: $0.label, rect: $0.box)
                }
                snapshots.save(buffer, boxes: drawn)
            }
            finish(&log)
            note(trackerMilliseconds + milliseconds)
            return log
        }

        /// A frame while counting is on and nothing is eligible and nothing moved on it.
        private func finish(_ log: inout LiveCountFrameLog) {
            log.tallyTotal = counter.tallyTotal
            log.mapTotal = counter.helperTotal
            log.model = model.rawValue
            log.units = units.rawValue
        }

        private func note(_ milliseconds: Double) {
            recentMilliseconds.append(milliseconds)
            if recentMilliseconds.count > Self.windowFrames {
                recentMilliseconds.removeFirst(recentMilliseconds.count - Self.windowFrames)
            }
            if !runsEverySecond, let p95 = analysisPercentiles?.p95,
                p95 > Self.slowAnalysisMilliseconds
            {
                runsEverySecond = true
            }
        }

        /// The screen's view of the count.
        func info(isActive: Bool, frameSize: CGSize) -> LiveCountInfo {
            lock.lock()
            let failure = loadFailure
            let opened = loadMilliseconds
            let isLoading = loadingGeneration != nil
            lock.unlock()
            var labels: [String: LiveCountInfo.LabelCount] = [:]
            for (label, count) in counter.helperCountByLabel {
                labels[label, default: .init(label: label, map: 0, tally: 0)].map = count
            }
            for (label, count) in counter.tallyCountByLabel {
                labels[label, default: .init(label: label, map: 0, tally: 0)].tally = count
            }
            return LiveCountInfo(
                isActive: isActive, total: counter.helperTotal, tallyTotal: counter.tallyTotal,
                labels: labels.values.sorted { $0.map != $1.map ? $0.map > $1.map : $0.label < $1.label },
                boxes: counter.visibleBoxes.map {
                    .init(
                        id: $0.id, label: $0.label, confidence: $0.confidence, rect: $0.box,
                        status: $0.status)
                },
                frameSize: frameSize, framesCounted: counter.framesCounted,
                framesSkipped: counter.framesSkippedByReason, hapticCount: hapticCount,
                problem: failure, runsEverySecondFrame: runsEverySecond,
                detectorModel: model.rawValue, detectorUnits: units.rawValue, discDrops: counter.discDrops,
                bigDrops: counter.bigDrops, loadMilliseconds: opened, isLoadingModel: isLoading)
        }
    }
#endif
