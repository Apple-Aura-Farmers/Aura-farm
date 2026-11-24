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
    /// The model's output layout, on the first decode only.
    var outputLayout: String?
    /// For a result that arrived after its frame: when that frame was taken (run seconds),
    /// and where the detection's time went, in milliseconds.
    var frameSeconds: Double?
    var preMilliseconds: Double?
    var inferMilliseconds: Double?
    var decodeMilliseconds: Double?
}

/// One camera buffer on its way to the detector queue. The detector queue empties it as soon
/// as it is done, so at most one buffer is ever held (see `LiveCountSession.process`).
private final class HeldBuffer {
    var buffer: CVPixelBuffer?
    init(_ buffer: CVPixelBuffer) { self.buffer = buffer }
}

/// Runs the detector on the frames the guide's counting rules let through and feeds
/// `LiveOrganismCounter`.
///
/// Two queues. The analysis queue (the lab's) calls `process` for every analysed frame and gets
/// its answer at once. The model runs on a serial queue of its own, "slidelab.detector": the
/// detector, the counter and the snapshots all live there, so the analysis queue never waits
/// for it (V2 takes about 30 ms a frame on the phone). Each frame sends the detector queue ONE
/// note, in order:
/// - a skip, with the frame's picture shift, for every frame the counting rules or the model
///   being busy turned away, or
/// - a detect, for a frame the model may look at, only when no detect is still pending or
///   running. Otherwise that frame becomes a skip with the reason "busy".
/// Every note carries its frame's shift and the notes are handled in order, so the counter's
/// carried shift stays exact and an organism straddling busy frames is the same track.
///
/// A detect holds the camera buffer until it is done and no second one is sent meanwhile, so
/// at most one buffer is held. Reset, a new run, a model change and counting starting or
/// stopping are notes on the same queue. A result that was running when a reset or a model
/// change was asked for is thrown away (`epoch`) and counted into nothing.
///
/// The detector opens off both queues (`prepare()`), on the Neural Engine by default. Until it
/// is ready, frames are skipped as "model_loading".
final class LiveCountSession {
    /// What runs the model: opened detector by default; a test puts a slow one in.
    typealias Detect = (CVPixelBuffer, CGRect?) throws -> (
        found: [OrganismDetector.Detection], timing: OrganismDetector.Timing
    )

    /// Settings, set from the lab's switches (through the analysis queue).
    var isEnabled = true
    /// On by default: V2 calls the whole bright eyepiece disc Volvox or Nematode without it.
    var cropsToEyepiece = true
    var minimumConfidence = OrganismDetector.leastConfidence
    /// Which model counts. Change it with `setModel` only.
    private(set) var model = DetectorModel.v3
    /// The hardware it runs on (`defaultUnits` until changed). Change it with `setUnits` only.
    private(set) var units = LiveCountSession.defaultUnits
    /// The Neural Engine in Release, for power per inference. Debug builds use the graphics chip,
    /// which skips the Neural Engine's long first-load preparation after every reinstall.
    #if DEBUG
        static let defaultUnits = DetectorUnits.graphics
    #else
        static let defaultUnits = DetectorUnits.neuralEngine
    #endif
    /// Called on the detector queue after a result is in the count, so the screen need not
    /// wait for the next analysed frame.
    var onResult: (() -> Void)?

    private let loadQueue = DispatchQueue(label: "slidelab.detector-load", qos: .userInitiated)
    private let detectorQueue = DispatchQueue(label: "slidelab.detector", qos: .userInitiated)
    private let injected: Detect?
    /// Guards everything below that the two queues share.
    private let lock = NSLock()
    private var loaded: OrganismDetector?
    private var loadingGeneration: Int?
    private var generation = 0
    private var wanted = (model: DetectorModel.v3, units: LiveCountSession.defaultUnits)
    private var loadFailure: String?
    private var loadMilliseconds: Double?
    /// When the detector last ran, on the run's clock.
    private var lastDetectedAt: Double?
    /// Counts the runs and model changes. A detect that finishes under another epoch is dropped.
    private var epoch = 0
    /// A detect note is pending or running.
    private var detectInFlight = false
    /// Results that arrived and are not yet in a CSV row, oldest first.
    private var completed: [LiveCountFrameLog] = []
    private var counting = false
    private var counterState = LiveOrganismCounter()
    private var hapticCount = 0
    // Detections shown while the stage is moved by hand: nothing here reaches the count.
    private var previewing = false
    private var previewEpoch = 0
    private var previewInFlight = false
    private var previewBoxes: [LiveCountInfo.Box] = []
    /// Run seconds of the last preview result, for the preview's own skip rules.
    private var previewResultAt: Double?

    // Detector queue only.
    private let snapshots = DetectionSnapshotWriter()
    private let crops = OrganismCropWriter()
    /// The crop file of each counted entry (by map entry id), for the run record. Under `lock`.
    private var cropFiles: [Int: String] = [:]
    private var lastHapticAt = -Double.infinity
    // Analysis queue only.
    private var lastCircle: FieldCircle?

    init(detect: Detect? = nil) {
        injected = detect
    }

    /// A copy of the counter as it is now.
    var counter: LiveOrganismCounter {
        lock.lock()
        defer { lock.unlock() }
        return counterState
    }

    /// A new run: counts and snapshots start afresh. The model stays open. A detection that is
    /// running is thrown away.
    func begin(stamp: String) {
        restart { [snapshots, crops] in
            snapshots.begin(stamp: stamp)
            crops.begin(stamp: stamp)
        }
    }

    /// Counting starts or stops (the guide's `countingActive`). A note like the others, so it
    /// is seen in order with the frames around it.
    func setCounting(_ isOn: Bool) {
        detectorQueue.async { [self] in
            lock.lock()
            counting = isOn
            lock.unlock()
        }
    }

    /// Starts or ends showing detections without counting them (the stage moved by hand). Either
    /// way the boxes are cleared, and a result still running is dropped when it arrives.
    func setPreviewing(_ isOn: Bool) {
        lock.lock()
        if previewing != isOn {
            previewing = isOn
            previewEpoch += 1
        }
        previewBoxes = []
        previewResultAt = nil
        lock.unlock()
    }

    /// How long ago a preview result came, on the run's clock; nil if none has.
    func secondsSincePreview(at seconds: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return previewResultAt.map { seconds - $0 }
    }

    /// Whether the detector queue has been told counting is on, once it has caught up.
    var isCounting: Bool {
        lock.lock()
        defer { lock.unlock() }
        return counting
    }

    /// Waits until the detector queue has handled everything sent so far. For the end of a run
    /// and for tests; the analysis queue never needs it per frame.
    func drain() {
        detectorQueue.sync {}
        crops.flush()
    }

    /// The crop saved for a map entry; nil if it has none.
    func cropFile(forEntry id: Int) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return cropFiles[id]
    }

    /// How long ago the detector last ran, on the run's clock; nil if it has not.
    func secondsSinceDetection(at seconds: Double) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return lastDetectedAt.map { seconds - $0 }
    }

    /// The oldest detection result not yet written to a CSV row. Each is handed out once.
    func takeCompleted() -> LiveCountFrameLog? {
        lock.lock()
        defer { lock.unlock() }
        return completed.isEmpty ? nil : completed.removeFirst()
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
        let all = names ?? model.builtInClassNames
        return (minimumConfidence, cropsToEyepiece, Array(all.dropFirst()))
    }

    // MARK: Starting afresh

    /// Asks for a clean count: running detections are dropped from now on, and the counter is
    /// emptied once the detector queue gets there.
    private func restart(_ then: @escaping () -> Void = {}) {
        lock.lock()
        epoch += 1
        lastDetectedAt = nil
        completed = []
        counterState.reset()
        cropFiles = [:]
        hapticCount = 0
        lock.unlock()
        detectorQueue.async { [self] in
            lock.lock()
            counterState.reset()
            cropFiles = [:]
            hapticCount = 0
            completed = []
            lock.unlock()
            lastHapticAt = -Double.infinity
            then()
        }
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
        restart()
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
        let skip =
            injected != nil || loaded != nil || loadingGeneration == ticket || loadFailure != nil
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

    // MARK: Frames

    /// One analysed frame while counting is on (the guide's `countingActive`). Analysis queue.
    /// Returns at once: a frame sent to the model comes back with `ran` false, and its result
    /// turns up later in `takeCompleted()`.
    /// - Parameters:
    ///   - skipReason: why this frame may not go to the detector (see
    ///     `LiveOrganismCounter.skipReason`), nil when it may.
    ///   - trackerPosition: `SlideMovementStep.position`, px.
    func process(
        buffer: CVPixelBuffer, skipReason: String?, pictureMoved: CGPoint,
        trackerPosition: CGPoint, frameSize: CGSize, fieldCircle: FieldCircle?, seconds: Double,
        column: Int, fieldSide: Double = 1
    ) -> LiveCountFrameLog {
        var log = LiveCountFrameLog(active: true)
        log.model = model.rawValue
        log.units = units.rawValue
        if let fieldCircle { lastCircle = fieldCircle }
        guard isEnabled else {
            log.skipReason = "off"
            return log
        }
        var reason = skipReason
        if reason == nil, !isReady {
            prepare()
            lock.lock()
            let failed = loadFailure != nil
            lock.unlock()
            reason = failed ? "no_model" : "model_loading"
        }
        var ticket = 0
        if reason == nil {
            lock.lock()
            if detectInFlight {
                reason = "busy"
            } else {
                detectInFlight = true
                ticket = epoch
            }
            lock.unlock()
        }
        if let reason {
            detectorQueue.async { [self] in
                lock.lock()
                counterState.skip(pictureMoved: pictureMoved, reason: reason)
                lock.unlock()
            }
            log.skipReason = reason
            finish(&log)
            return log
        }
        var crop: CGRect?
        if cropsToEyepiece, let circle = lastCircle {
            crop = FieldCentring.cropRect(for: circle, frameSize: frameSize)
        }
        let held = HeldBuffer(buffer)
        let confidence = minimumConfidence
        let circle = fieldCircle ?? lastCircle
        detectorQueue.async { [self] in
            detect(
                held, ticket: ticket, confidence: confidence, crop: crop, circle: circle,
                pictureMoved: pictureMoved, trackerPosition: trackerPosition,
                frameSize: frameSize, seconds: seconds, column: column, fieldSide: fieldSide)
        }
        finish(&log)
        return log
    }

    /// One analysed frame while the stage is moved by hand: the same rules decide whether the
    /// detector looks (`skipReason`, made with the paused rule off), but the result only goes to
    /// the preview boxes. The counter, the tally, the map, the crops, the haptics and the run's
    /// detection clock are not touched. Analysis queue.
    /// - Parameter moved: the picture is moving; the boxes are then cleared once no result has
    ///   come for a second. A still view keeps them.
    func processPreview(
        buffer: CVPixelBuffer, skipReason: String?, moved: Bool, frameSize: CGSize,
        fieldCircle: FieldCircle?, seconds: Double
    ) {
        if let fieldCircle { lastCircle = fieldCircle }
        lock.lock()
        guard previewing, isEnabled else {
            lock.unlock()
            return
        }
        if moved, seconds - (previewResultAt ?? -.infinity) > 1 { previewBoxes = [] }
        var reason = skipReason
        if reason == nil, !(injected != nil || loaded != nil) { reason = "model_loading" }
        if reason == nil, previewInFlight { reason = "busy" }
        guard reason == nil else {
            lock.unlock()
            if reason == "model_loading" { prepare() }
            return
        }
        previewInFlight = true
        let ticket = previewEpoch
        lock.unlock()
        var crop: CGRect?
        if cropsToEyepiece, let circle = lastCircle {
            crop = FieldCentring.cropRect(for: circle, frameSize: frameSize)
        }
        let held = HeldBuffer(buffer)
        let confidence = minimumConfidence
        let circle = fieldCircle ?? lastCircle
        detectorQueue.async { [self] in
            detectPreview(
                held, ticket: ticket, confidence: confidence, crop: crop, circle: circle,
                frameSize: frameSize, seconds: seconds)
        }
    }

    /// The preview's detect note. Detector queue.
    private func detectPreview(
        _ held: HeldBuffer, ticket: Int, confidence: Float, crop: CGRect?, circle: FieldCircle?,
        frameSize: CGSize, seconds: Double
    ) {
        guard let buffer = held.buffer else { return }
        var run = injected
        if run == nil, var detector = readyDetector() {
            detector.minimumConfidence = confidence
            run = { try detector.timedDetections(in: $0, crop: $1) }
        }
        let found = run.flatMap { try? $0(buffer, crop) }?.found ?? []
        held.buffer = nil
        lock.lock()
        previewInFlight = false
        // The hold ended (or began again) while the model ran: the result belongs to nothing.
        guard previewing, previewEpoch == ticket else {
            lock.unlock()
            return
        }
        let drops = counterState.dropsOutsideField
        let guards = counterState.guards
        var boxes: [LiveCountInfo.Box] = []
        for detection in found where detection.confidence >= confidence {
            let box = OrganismTally.Found(
                detection, frameWidth: Double(frameSize.width), frameHeight: Double(frameSize.height)
            ).box
            if drops, let circle,
                hypot(Double(box.midX - circle.centre.x), Double(box.midY - circle.centre.y))
                    > circle.radius
            {
                continue
            }
            if guards.drop(box: box, crop: crop, circle: circle) != nil { continue }
            boxes.append(
                .init(
                    id: boxes.count + 1, label: detection.label, confidence: detection.confidence,
                    rect: box, status: .notCounted))
        }
        previewBoxes = boxes
        previewResultAt = seconds
        lock.unlock()
        onResult?()
    }

    private var isReady: Bool {
        lock.lock()
        defer { lock.unlock() }
        return injected != nil || loaded != nil
    }

    /// The detect note. Detector queue.
    private func detect(
        _ held: HeldBuffer, ticket: Int, confidence: Float, crop: CGRect?, circle: FieldCircle?,
        pictureMoved: CGPoint, trackerPosition: CGPoint, frameSize: CGSize, seconds: Double,
        column: Int, fieldSide: Double
    ) {
        guard let buffer = held.buffer else { return }
        var run = injected
        if run == nil, var detector = readyDetector() {
            detector.minimumConfidence = confidence
            run = { try detector.timedDetections(in: $0, crop: $1) }
        }
        guard let run else {
            // Closed by a model change while this note waited: nothing was looked at.
            lock.lock()
            counterState.skip(pictureMoved: pictureMoved, reason: "model_loading")
            detectInFlight = false
            lock.unlock()
            held.buffer = nil
            return
        }
        let started = CACurrentMediaTime()
        let output = (try? run(buffer, crop)) ?? (found: [], timing: OrganismDetector.Timing())
        let milliseconds = (CACurrentMediaTime() - started) * 1000

        lock.lock()
        guard epoch == ticket else {
            // A reset or a model change came while the model ran: this belongs to no run.
            detectInFlight = false
            lock.unlock()
            held.buffer = nil
            return
        }
        let result = counterState.update(
            detections: output.found, pictureMoved: pictureMoved,
            trackerPosition: trackerPosition, frameSize: frameSize, fieldCircle: circle,
            crop: crop, seconds: seconds, column: column, fieldSide: fieldSide)
        lastDetectedAt = seconds
        var log = LiveCountFrameLog(active: true)
        log.ran = true
        log.milliseconds = milliseconds
        log.found = result.found
        log.outside = result.outsideField
        log.newInTally = result.newInTally
        log.newOnMap = result.newOnMap
        log.repeatOnMap = result.repeatOnMap
        log.droppedDisc = result.droppedDisc
        log.droppedBig = result.droppedBig
        log.frameSeconds = seconds
        log.preMilliseconds = output.timing.preMilliseconds
        log.inferMilliseconds = output.timing.inferMilliseconds
        log.decodeMilliseconds = output.timing.decodeMilliseconds
        log.outputLayout = output.timing.outputLayout
        log.tallyTotal = counterState.tallyTotal
        log.mapTotal = counterState.helperTotal
        log.model = model.rawValue
        log.units = units.rawValue
        for entry in result.newEntries {
            log.counted.append(
                "\(entry.label) id=\(entry.id) slide=(\(Int(entry.position.x)),\(Int(entry.position.y))) column=\(entry.column)"
                    + String(format: " map=(%.2f,%.2f)", entry.fields.x, entry.fields.y)
            )
        }
        var cropItems: [(id: Int, box: CGRect)] = []
        for entry in result.newEntries {
            guard let box = result.newBoxes[entry.id] else { continue }
            cropFiles[entry.id] = OrganismCropWriter.fileName(id: entry.id)
            cropItems.append((entry.id, box))
        }
        var drawn: [(id: Int, label: String, rect: CGRect)] = []
        if !result.newEntries.isEmpty {
            if seconds - lastHapticAt >= 0.5 {
                lastHapticAt = seconds
                hapticCount += 1
            }
            drawn = counterState.visibleBoxes.filter { $0.status == .counted }.map {
                (id: $0.id, label: $0.label, rect: $0.box)
            }
        }
        completed.append(log)
        lock.unlock()

        if !drawn.isEmpty { snapshots.save(buffer, boxes: drawn) }
        crops.save(buffer, items: cropItems)
        held.buffer = nil
        lock.lock()
        detectInFlight = false
        lock.unlock()
        onResult?()
    }

    /// What the counter and the model say about a frame, for the CSV.
    private func finish(_ log: inout LiveCountFrameLog) {
        lock.lock()
        log.tallyTotal = counterState.tallyTotal
        log.mapTotal = counterState.helperTotal
        lock.unlock()
    }

    /// The screen's view of the count.
    func info(isActive: Bool, frameSize: CGSize) -> LiveCountInfo {
        lock.lock()
        let failure = loadFailure
        let opened = loadMilliseconds
        let isLoading = loadingGeneration != nil
        let counter = counterState
        let haptics = hapticCount
        let preview = previewBoxes
        let isPreviewing = previewing
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
            previewBoxes: preview, isPreviewing: isPreviewing,
            dots: counter.map.entries.map {
                RunMapOrganism(
                    label: $0.label, x: Double($0.fields.x), y: Double($0.fields.y),
                    column: $0.column, seconds: $0.firstSeenSeconds)
            },
            frameSize: frameSize, framesCounted: counter.framesCounted,
            framesSkipped: counter.framesSkippedByReason, hapticCount: haptics,
            problem: failure,
            detectorModel: model.rawValue, detectorUnits: units.rawValue, discDrops: counter.discDrops,
            bigDrops: counter.bigDrops, loadMilliseconds: opened, isLoadingModel: isLoading)
    }
}
