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
        /// "Volvox id=7 slide=(12,-40) column=2", one per organism counted on this frame.
        var counted: [String] = []
    }

    /// Runs the detector on the frames the guide's counting rules let through and feeds
    /// `LiveOrganismCounter`. Analysis queue only. The detector opens once, on the first frame that
    /// needs it, on the CPU and GPU (measured 5.1 ms a frame on an iPhone 17 in `CaptureViewModel`).
    final class LiveCountSession {
        /// Settings, set from the lab's switches (through the analysis queue).
        var isEnabled = true
        var cropsToEyepiece = false
        var minimumConfidence = OrganismDetector.leastConfidence

        /// If the analysis p95 goes above this, only every second eligible frame is detected.
        /// PLACEHOLDER: about 80% of the 100 ms between analysed frames at 10 fps.
        static let slowAnalysisMilliseconds = 80.0
        private static let windowFrames = 60

        private(set) var counter = LiveOrganismCounter()
        private var detector: OrganismDetector?
        private var problem: String?
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
        }

        var framesDetected: Int { counter.framesCounted }
        var detectorOptions: (confidence: Float, crop: Bool, classes: [String]) {
            (minimumConfidence, cropsToEyepiece, Array(OrganismDetector.classNames.dropFirst()))
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
            guard openDetector() else {
                counter.skip(pictureMoved: pictureMoved, reason: "no_model")
                log.skipReason = "no_model"
                note(trackerMilliseconds)
                return log
            }
            guard var detector else { return log }
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
                frameSize: frameSize, fieldCircle: fieldCircle ?? lastCircle, seconds: seconds,
                column: column)
            log.ran = true
            log.milliseconds = milliseconds
            log.found = result.found
            log.outside = result.outsideField
            log.newInTally = result.newInTally
            log.newOnMap = result.newOnMap
            log.repeatOnMap = result.repeatOnMap
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

        private func openDetector() -> Bool {
            if detector != nil { return true }
            guard problem == nil else { return false }
            do {
                detector = try OrganismDetector(computeUnits: .cpuAndGPU)
                return true
            } catch {
                problem = error.localizedDescription
                return false
            }
        }

        /// The screen's view of the count.
        func info(isActive: Bool, frameSize: CGSize) -> LiveCountInfo {
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
                problem: problem, runsEverySecondFrame: runsEverySecond)
        }
    }
#endif
