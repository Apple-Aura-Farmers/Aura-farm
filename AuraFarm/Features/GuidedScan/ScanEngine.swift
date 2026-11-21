import AVFoundation
import Observation

/// Seconds of stillness the lab's stops test asks for (its haptic fires at it).
let slideLabStillGoalSeconds = 2.0

/// The camera and the analysis behind the guided scan and the slide movement lab (session queue,
/// analysis queue, 720p, locked focus, 420f frames). Frames are analyzed off the main thread; UI state is only changed on the main
/// queue.
///
/// Debug builds only. Measurement tooling: nothing here is saved to `FrameSets`; the CSV
/// goes to a temporary file for sharing.
@Observable
class ScanEngine: NSObject {
    /// The lens position the camera is locked at (autofocus hunts on a microscope).
    static let defaultLensPosition: Float = 1.0

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
    /// Live organism counting: the count, the boxes and the settings that shape them.
    private(set) var countInfo = LiveCountInfo()
    private(set) var showsDetections = false
    /// The hardware the counting model runs on, and the camera's rate.
    private(set) var detectorUnits = DetectorUnits.neuralEngine
    private(set) var cameraRate = CameraRate.fps20
    /// What the camera did with the 20 fps request, or why it did not (empty at 30 fps).
    private(set) var cameraNote = ""
    /// "nominal", "fair", "serious" or "critical", for the badge.
    private(set) var thermalState = "nominal"
    // Published at full rate, because the helper steers by them or they mark events.
    private(set) var hapticInfo = SlideMovementInfo.Haptics()
    private(set) var runControl = SlideMovementInfo.RunControl()
    /// The detection boxes, at full rate while "Show detections" is on.
    private(set) var liveBoxes = LiveCountInfo()
    let speedState = SlideMovementInfo.SpeedState()
    /// The model counting. It is locked from Mark start until the run finishes or the guide
    /// starts afresh, so a run never mixes models.
    private(set) var detectorModel = DetectorModel.v2
    private(set) var runMarked = false
    var modelLocked: Bool { runMarked || countInfo.isActive }
    private(set) var spotMode = SpotConfirmMode.briefTouch
    /// What the run came to, once the route finishes; with the files to share.
    private(set) var runSummary: GuideRunRecord?
    private(set) var summaryItems: [URL] = []
    /// Counts the haptic for "End now" and "End after this column".
    private(set) var endActionCount = 0
    /// The setup's state: align, focus, field, done. See `LabSetupSession`.
    private(set) var setupInfo = LabSetupInfo()
    /// The focus meter's value, on every analyzed frame.
    let focusMeter = FocusMeterState()
    /// The CSV of the setup log, once exported.
    /// Whether the next session starts at the field step, skipping align and focus.
    private(set) var skipsAlignAndFocus = false
    /// Whether the guide pauses when the run monitor sees the picture out of alignment or
    /// out of focus. The monitor logs either way.
    private(set) var pausesOnMonitor = true
    /// What the guide overlay draws, published on every analyzed frame; a value of its own
    /// so nothing else redraws that often.
    let overlayState = GuideOverlayState()
    /// The edge line's path, for the cyan overlay.
    let edgeLineState = EdgeLineState()
    /// The "What the app sees" picture, when it is switched on.
    private(set) var thumbnailImage: CGImage?
    private(set) var showsThumbnail = false
    private(set) var fieldRegion = FieldRegionMode.auto
    private(set) var measuresHopAgreement = false
    /// A brief confirmation after Mark start or Mark end ("Mark start ✓").
    private(set) var markToast: String?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    private(set) var cameraError: String?
    private(set) var lensPosition = ScanEngine.defaultLensPosition
    private(set) var isLogging = false
    /// False while the person is setting the phone up: the camera runs so they can position
    /// and focus it, but nothing is analyzed until they tap Start.
    private(set) var isAnalyzing = false
    private(set) var rowCount = 0
    /// The CSV of the last log that was stopped with rows in it.
    private(set) var exportURL: URL?
    /// The CSV and the frames saved while logging, shared together.
    private(set) var exportItems: [URL] = []

    // MARK: Hooks for the lab (analysis queue)

    /// The lab layer's extras (labels, statistics) hang on these; the engine itself does
    /// nothing with them.
    @ObservationIgnored var onLogStarted: (() -> Void)?
    @ObservationIgnored var onRowLogged: ((MovementLogRow, Double) -> Void)?
    @ObservationIgnored var onLogStopped: (() -> Void)?

    // MARK: Camera

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "slidelab.session")
    @ObservationIgnored let analysisQueue = DispatchQueue(label: "slidelab.analysis")
    @ObservationIgnored private var confirmsSetupSteps = false
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var device: AVCaptureDevice?

    // MARK: Analysis (analysis queue only)

    @ObservationIgnored var pipeline: SlideMovementPipeline = {
        let pipeline = SlideMovementPipeline()
        pipeline.requiresReview = true
        return pipeline
    }()
    @ObservationIgnored private let dryRun = GuideDryRun()
    @ObservationIgnored private let edgeProbe = EdgeLineProbe()
    @ObservationIgnored private let snapshots = FrameSnapshotWriter()
    @ObservationIgnored private let live = LiveCountSession()
    @ObservationIgnored private var lastCountInfo = LiveCountInfo()
    @ObservationIgnored private var lastCountingActive = false
    @ObservationIgnored private var lastCountFrameSize = CGSize.zero
    @ObservationIgnored private var runStartedAt: Date?
    @ObservationIgnored private var runStartSeconds = 0.0
    @ObservationIgnored private var runFinalized = false
    @ObservationIgnored private var snapshotTrigger = SnapshotTrigger()
    @ObservationIgnored var snapshotRequested = false
    /// A tap on an edge button waiting for the next logged row: it names the row, saves a
    /// frame, and is answered to the guide.
    @ObservationIgnored private var pendingEdgeFeedback: EdgeFeedback?
    @ObservationIgnored private var lastFrameSeconds = 0.0
    @ObservationIgnored private var guideEnabled = false
    @ObservationIgnored var setup = LabSetupSession()
    @ObservationIgnored private var lastPublishedStep = LabSetupStep.align
    @ObservationIgnored private var pausesOnMonitorFlag = true
    @ObservationIgnored var pendingEventName = ""
    @ObservationIgnored private var latestGuide: GuideRowFields?
    @ObservationIgnored private var latestGuideInfo = SlideMovementInfo.Guide()
    @ObservationIgnored private var guideCaptured: [CGPoint] = []
    @ObservationIgnored private var guideTarget: CGPoint?
    @ObservationIgnored private var guidePredicted: [PredictedTrailLine] = []
    @ObservationIgnored private var guideEdgePoints: [CGPoint] = []
    /// The words the guided scan page shows now, written in each logged row. Analysis queue.
    @ObservationIgnored private var helperWords = ""
    /// "Show life on map": the organisms and edge points are drawn on the mini-map.
    @ObservationIgnored private var showsLifeOnMap = true
    /// The run's path in the trail's space, thinned as it grows, for the run record's map.
    @ObservationIgnored private var runPath: [CGPoint] = []
    @ObservationIgnored private var frameCount = 0
    @ObservationIgnored private var analyzing = false
    /// Analyze every Nth frame: about 10 fps at 30 fps capture.
    /// 2 at 20 fps, 3 at 30 fps: the same nominal 10 analysed frames a second. Analysis queue.
    @ObservationIgnored private var analyzeEveryNthFrame = CameraRate.fps20.analyzeEveryNthFrame
    /// The camera rate to configure with. Session queue.
    @ObservationIgnored private var sessionCameraRate = CameraRate.fps20
    @ObservationIgnored private var logging = false
    @ObservationIgnored private var rows: [MovementLogRow] = []
    @ObservationIgnored private var logOrigin: Double?
    @ObservationIgnored var currentLabel = ""
    @ObservationIgnored var pendingMark = MarkSlot()
    @ObservationIgnored private var trailBlind: [Bool] = []
    @ObservationIgnored private var trail: [CGPoint] = []
    @ObservationIgnored private var lastEventName = ""
    @ObservationIgnored private var indicators = MovementIndicators()
    @ObservationIgnored var currentTest = SlideLabTest.free
    @ObservationIgnored var currentNote = ""
    @ObservationIgnored private var latestPositionFields = CGPoint.zero
    @ObservationIgnored private var startTrailPoint: CGPoint?
    @ObservationIgnored private var hopPoints: [CGPoint] = []
    @ObservationIgnored private var lostPoints: [CGPoint] = []
    @ObservationIgnored private var hopCount = 0
    @ObservationIgnored private var lostCount = 0
    /// About 6 seconds of trail at 10 fps.
    @ObservationIgnored private let trailLength = 60
    /// Everything the panels show except what the helper steers by, paced to
    /// `ScreenUpdateThresholds.updatesPerSecond` with the latest value always arriving.
    @ObservationIgnored private let panelThrottle = MainThrottle<PanelUpdate>()
    @ObservationIgnored private let setupThrottle = MainThrottle<LabSetupInfo>()
    @ObservationIgnored private let countThrottle = MainThrottle<LiveCountInfo>()
    @ObservationIgnored private let thumbnailThrottle = MainThrottle<CGImage>()
    @ObservationIgnored private let deviceStatus = LabDeviceStatus()
    @ObservationIgnored private var lastHaptics = SlideMovementInfo.Haptics()
    @ObservationIgnored private var lastRunControl = SlideMovementInfo.RunControl()
    @ObservationIgnored private var lastSpeed = (
        fraction: -1.0, status: MovementIndicators.Status.starting
    )
    @ObservationIgnored private var showsDetectionsFlag = false
    /// Capture timestamps of the last second, for `camera_fps`.
    @ObservationIgnored private var frameTimes: [Double] = []
    /// Frames the output dropped as late so far (`camera_drops`); `camera_fps` counts only the
    /// frames that were delivered, so drops make it read low. Analysis queue.
    @ObservationIgnored private var lateFrameDrops = 0
    /// What the device was doing after `applyCameraRate` and on the first frame after it, for the
    /// console and, once, the CSV (`camera_config` event). Analysis queue.
    @ObservationIgnored private var cameraConfigText = ""
    @ObservationIgnored private var cameraConfigPending = false
    @ObservationIgnored private var reportsRunningConfig = false
    @ObservationIgnored private var lastAnalysedAt: Double?
    @ObservationIgnored private var measureAgreementEnabled = false
    /// The edge questions raised this run, and the id the next row's event refers to. Analysis queue.
    @ObservationIgnored private var edgeQuestions = EdgeQuestionBook()
    @ObservationIgnored private var lastEdgeReachedCount = 0
    @ObservationIgnored private var pendingEdgeQuestionID: Int?
    /// The `side_inset` event has been written for this run. Analysis queue.
    @ObservationIgnored private var sideInsetLogged = false

    /// What the throttled panels are set to, in one piece.
    struct PanelUpdate {
        var setup: LabSetupInfo
        var status: SlideMovementInfo.Status
        var readouts: SlideMovementInfo.Readouts
        var trail: SlideMovementInfo.Trail
        var field: SlideMovementInfo.Field
        var guide: SlideMovementInfo.Guide
        var rowCount: Int
        var isLogging: Bool
        var thermal: String
    }

    override init() {
        super.init()
        panelThrottle.apply = { [weak self] in self?.apply($0) }
        setupThrottle.apply = { [weak self] info in
            guard let self else { return }
            if self.setupInfo != info { self.setupInfo = info }
            if self.fieldInfo != SlideMovementInfo.Field() {
                self.fieldInfo = SlideMovementInfo.Field()
            }
        }
        countThrottle.apply = { [weak self] in self?.countInfo = $0 }
        live.onResult = { [weak self] in self?.detectionFinished() }
        thumbnailThrottle.apply = { [weak self] image in
            guard let self, self.showsThumbnail else { return }
            self.thumbnailImage = image
        }
    }

    private func apply(_ update: PanelUpdate) {
        if setupInfo != update.setup { setupInfo = update.setup }
        if statusInfo != update.status { statusInfo = update.status }
        if readouts != update.readouts { readouts = update.readouts }
        if trailInfo != update.trail { trailInfo = update.trail }
        if fieldInfo != update.field { fieldInfo = update.field }
        if guideInfo != update.guide { guideInfo = update.guide }
        if update.isLogging, rowCount != update.rowCount { rowCount = update.rowCount }
        if thermalState != update.thermal { thermalState = update.thermal }
    }

    // MARK: Lifecycle

    func start() {
        deviceStatus.begin()
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

    /// Whether a session starts at the field step: "Skip align and focus".
    func setSkipsAlignAndFocus(_ skips: Bool) {
        skipsAlignAndFocus = skips
    }

    /// The guided scan page confirms align and focus with a button; the lab does not.
    func setConfirmsSetupSteps(_ confirms: Bool) {
        confirmsSetupSteps = confirms
        analysisQueue.async { [weak self] in self?.setup.confirmsSteps = confirms }
    }

    /// The person tapped Confirm on the align or focus step.
    func confirmSetupStep() {
        analysisQueue.async { [weak self] in self?.setup.confirmStep() }
    }

    /// Whether the guide pauses on the run monitor's say.
    func setPausesOnMonitor(_ pauses: Bool) {
        pausesOnMonitor = pauses
        analysisQueue.async { [weak self] in self?.pausesOnMonitorFlag = pauses }
    }

    /// Whether the guide takes edges from the cover slip's line only ("Full cover slip").
    func setFullCoverSlip(_ enabled: Bool) {
        analysisQueue.async { [weak self] in
            guard let self, self.dryRun.fullCoverSlip != enabled else { return }
            self.dryRun.fullCoverSlip = enabled
            self.resetGuide()
        }
    }

    /// Whether the tracker follows a sparse but distinct sample ("Track sparse sample").
    func setTracksSparse(_ tracks: Bool) {
        analysisQueue.async { [weak self] in self?.pipeline.tracksSparse = tracks }
    }

    /// The helper says the stage cannot go further: the guide turns and remembers the limit.
    /// Written to the movement CSV as the event "stage_limit" ("stage_limit_auto" when the
    /// automated stage pressed it). Ignored unless the guide is on.
    func stageLimit(auto: Bool = false) {
        analysisQueue.async { [weak self] in
            guard let self, self.guideEnabled else { return }
            self.dryRun.stageLimitPressed = true
            self.pendingEventName = auto ? "stage_limit_auto" : "stage_limit"
        }
    }

    /// "Resume anyway" on the focus-pause banner. The run goes on and the focus baseline is
    /// measured again from the next readings.
    func resumeFocusAnyway() {
        analysisQueue.async { [weak self] in
            guard let self, self.setup.resumeFocusManually() else { return }
            self.pendingEventName = "focus_resume_manual"
            let info = self.setup.info
            DispatchQueue.main.async { self.setupInfo = info }
        }
    }

    /// Skips the stage step: the picture and the guide stay as they are (the identity).
    func skipStage() {
        analysisQueue.async { [weak self] in
            guard let self, self.setup.step == .stage else { return }
            self.setup.skipStage()
            self.lastPublishedStep = .done
            self.clearTrackingDisplay()
            self.resetGuide()
            let info = self.setup.info
            DispatchQueue.main.async { self.setupInfo = info }
        }
    }

    /// The lab's stage step starts again from X (the automated stage's own moves must not count).
    func restartStageMeasurement() {
        analysisQueue.async { [weak self] in
            guard let self, self.setup.step == .stage else { return }
            self.setup.restartStageMeasurement()
            let info = self.setup.info
            DispatchQueue.main.async { self.setupInfo = info }
        }
    }

    /// The automated stage measured the axes: the stage step is done with them.
    func completeStage(with axes: StageAxes) {
        analysisQueue.async { [weak self] in
            guard let self, self.setup.step == .stage else { return }
            self.setup.completeStage(with: axes)
            self.lastPublishedStep = .done
            self.clearTrackingDisplay()
            self.resetGuide()
            let info = self.setup.info
            DispatchQueue.main.async { self.setupInfo = info }
        }
    }

    /// Called on the main thread with the guide position, the tracking state and the time of every
    /// analysed frame while the setup step is stage or done (the automated stage measures from it).
    @ObservationIgnored var onGuideSample: ((CGPoint, TrackingState, Double) -> Void)? {
        didSet {
            let handler = onGuideSample
            analysisQueue.async { [weak self] in self?.guideSampleHandler = handler }
        }
    }
    /// Analysis queue's copy of `onGuideSample`.
    @ObservationIgnored private var guideSampleHandler: ((CGPoint, TrackingState, Double) -> Void)?

    /// Starts the setup of a session, on the analysis queue: at align, or at field when
    /// skipping, which learns the eyepiece mask afresh from the next frame.
    private func beginSetup() {
        let skips = skipsAlignAndFocus
        setup = LabSetupSession(skippingAlignAndFocus: skips)
        setup.confirmsSteps = confirmsSetupSteps
        pipeline.resetPosition()
        if skips { pipeline.redetectField() }
        clearTrackingDisplay()
        resetGuide()
        lastPublishedStep = setup.step
        analyzing = true
        let info = setup.info
        DispatchQueue.main.async {
            self.setupInfo = info
            self.focusMeter.update(nil)
            self.fieldInfo = SlideMovementInfo.Field()
            self.isAnalyzing = true
        }
    }

    /// All of the setup again, from align: any log is ended and the field is forgotten.
    func redoSetup() {
        stopLog()
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.setup.redo()
            self.pipeline.redetectField()
            self.clearTrackingDisplay()
            self.resetGuide()
            self.lastPublishedStep = .align
            let info = self.setup.info
            DispatchQueue.main.async {
                self.setupInfo = info
                self.focusMeter.update(nil)
                self.fieldInfo = SlideMovementInfo.Field()
            }
        }
    }

    /// Back to set-up: the camera keeps running, analysis pauses and any log is ended.
    func endAnalysis() {
        stopLog()
        panelThrottle.flush()
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.analyzing = false
            DispatchQueue.main.async { self.isAnalyzing = false }
        }
    }

    func stop() {
        panelThrottle.flush()
        countThrottle.flush()
        deviceStatus.end()
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

    /// Back to the field step: forgets the learned eyepiece mask and learns it again. Use
    /// after moving the phone or changing the light.
    func redetectField() {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.setup.redoField(pipeline: self.pipeline)
            self.clearTrackingDisplay()
            self.lastPublishedStep = .field
            let info = self.setup.info
            DispatchQueue.main.async { self.setupInfo = info }
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
            self.onLogStarted?()
            self.logging = true
            self.snapshots.begin()
            self.snapshotTrigger.reset()
            self.snapshotRequested = false
            DispatchQueue.main.async {
                self.exportItems = []
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
            let items = (url.map { [$0] } ?? []) + self.snapshots.urls
            let count = self.rows.count
            self.onLogStopped?()
            DispatchQueue.main.async {
                self.isLogging = false
                self.rowCount = count
                self.exportURL = url
                self.exportItems = items
            }
        }
    }

    /// The helper's answer about an edge, from the buttons on the guide overlay ("✓ Edge", "✗ Not
    /// an edge", "Mark edge here"). Written to the CSV as the event `edge_user_yes`,
    /// `edge_user_no` or `edge_user_mark`, with a frame saved.
    func edgeFeedback(_ feedback: EdgeFeedback) {
        analysisQueue.async { [weak self] in
            guard let self, self.guideEnabled else { return }
            self.dryRun.userEdge(feedback, seconds: self.lastFrameSeconds)
            self.pendingEdgeFeedback = feedback
        }
    }

    /// What became of one answer to an edge question.
    struct EdgeAnswerRecord: Equatable {
        enum Outcome: Equatable { case applied, late }
        var questionID: Int
        var feedback: EdgeFeedback
        var outcome: Outcome
    }

    /// The answers applied so far, in order. Analysis queue.
    @ObservationIgnored private(set) var edgeAnswerLog: [EdgeAnswerRecord] = []

    /// The helper's answer to the edge question on the card, by id. Queued on the analysis queue,
    /// so a busy queue delays an answer but never drops one, and answers apply in order. The edge
    /// the question was about is accepted or rejected even if the line has since left the cross.
    /// A question that was answered, replaced or has expired is late: logged as `edge_user_late`
    /// and ignored. Written to the CSV as `edge_user_yes`, `edge_user_no` or `edge_user_late`
    /// with `question=<id>`.
    func answerEdge(_ feedback: EdgeFeedback, questionID: Int) {
        analysisQueue.async { [weak self] in
            guard let self, self.guideEnabled else { return }
            self.pendingEdgeQuestionID = questionID
            if let question = self.edgeQuestions.answer(id: questionID),
                self.dryRun.answerEdgeQuestion(
                    question.snapshot, feedback, seconds: self.lastFrameSeconds)
            {
                self.pendingEdgeFeedback = feedback
                self.edgeAnswerLog.append(
                    EdgeAnswerRecord(questionID: questionID, feedback: feedback, outcome: .applied))
            } else {
                self.pendingEventName = "edge_user_late"
                self.edgeAnswerLog.append(
                    EdgeAnswerRecord(questionID: questionID, feedback: feedback, outcome: .late))
            }
        }
    }

    /// What the guided scan page shows as the instruction, for the CSV's `knob_words`.
    func setHelperWords(_ words: String) {
        analysisQueue.async { [weak self] in self?.helperWords = words }
    }

    /// Whether the guide asks the helper to confirm edges ("Ask me to confirm edges").
    func setAsksEdges(_ asks: Bool) {
        analysisQueue.async { [weak self] in
            guard let self, self.dryRun.asksEdges != asks else { return }
            self.dryRun.asksEdges = asks
            self.resetGuide()
        }
    }

    /// "Show life on map": dots for the organisms counted, on the mini-map.
    func setShowsLifeOnMap(_ shows: Bool) {
        analysisQueue.async { [weak self] in self?.showsLifeOnMap = shows }
    }

    /// "Cover slip": square lets the guide predict the right edge. Starts the guide afresh.
    func setCoverSlip(_ shape: CoverSlipShape) {
        analysisQueue.async { [weak self] in
            guard let self, self.dryRun.coverSlip != shape else { return }
            self.dryRun.coverSlip = shape
            self.resetGuide()
        }
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
        if !enabled {
            guideInfo = SlideMovementInfo.Guide()
            overlayState.model = nil
        }
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.guideEnabled = enabled
            self.resetGuide()
        }
    }

    private func resetGuide() {
        dryRun.reset()
        edgeProbe.reset()
        DispatchQueue.main.async { [edgeLineState] in edgeLineState.update([]) }
        latestGuide = nil
        latestGuideInfo = SlideMovementInfo.Guide()
        guideCaptured = []
        guideTarget = nil
        guidePredicted = []
        guideEdgePoints = []
        runPath = []
        sideInsetLogged = false
        edgeQuestions = EdgeQuestionBook()
        lastEdgeReachedCount = 0
        pendingEdgeQuestionID = nil
        // A new run: counting, its snapshots and the summary start afresh.
        live.begin(stamp: Self.stamp())
        live.setCounting(false)
        lastCountingActive = false
        lastCountInfo = LiveCountInfo()
        runStartedAt = nil
        runFinalized = false
        DispatchQueue.main.async { [weak self] in
            self?.countInfo = LiveCountInfo()
            self?.runSummary = nil
            self?.summaryItems = []
            self?.runMarked = false
        }
    }

    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: .now)
    }

    // MARK: Spot check, coverage, counting, ending

    /// "Spot check": brief touch or hold still. Starts the guide afresh.
    func setSpotMode(_ mode: SpotConfirmMode) {
        spotMode = mode
        analysisQueue.async { [weak self] in
            guard let self, self.dryRun.spotMode != mode else { return }
            self.dryRun.spotMode = mode
            self.resetGuide()
        }
    }

    /// "Coverage": fields between columns (0.8, 1.6 or 2.4). Starts the guide afresh.
    func setCoverageStep(_ fields: Double) {
        analysisQueue.async { [weak self] in
            guard let self, self.dryRun.coverageStep != fields else { return }
            self.dryRun.coverageStep = fields
            self.resetGuide()
        }
    }

    func setCountsOrganisms(_ counts: Bool) {
        analysisQueue.async { [weak self] in self?.live.isEnabled = counts }
    }

    func setShowsDetections(_ shown: Bool) {
        showsDetections = shown
        analysisQueue.async { [weak self] in
            self?.showsDetectionsFlag = shown
            // On: the boxes now, not at the next change of the count.
            let current = shown ? self?.lastCountInfo : LiveCountInfo()
            DispatchQueue.main.async { self?.liveBoxes = current ?? LiveCountInfo() }
        }
    }

    /// "Model chip": the Neural Engine or the graphics chip for the counting model. Locked like
    /// the model; reopens the detector off the main thread and starts the live count afresh.
    func setDetectorUnits(_ units: DetectorUnits) {
        guard !modelLocked, units != detectorUnits else { return }
        detectorUnits = units
        analysisQueue.async { [weak self] in
            self?.live.setUnits(units)
            self?.lastCountInfo = LiveCountInfo()
            DispatchQueue.main.async { self?.countInfo = LiveCountInfo() }
        }
    }

    /// "Camera": 20 fps (and every 2nd frame analysed) or the old 30 fps (every 3rd). Only
    /// before Mark start; reconfigures the running session.
    func setCameraRate(_ rate: CameraRate) {
        guard !modelLocked, rate != cameraRate || !isConfigured else { return }
        cameraRate = rate
        cameraNote = ""
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.sessionCameraRate = rate
            if self.isConfigured, let device = self.device { self.applyCameraRate(rate, to: device) }
        }
        analysisQueue.async { [weak self] in
            self?.analyzeEveryNthFrame = rate.analyzeEveryNthFrame
            self?.frameCount = 0
        }
    }

    /// "Model": V2 or V1 for live counting. Ignored while a run is on; the new model opens off
    /// the main thread and the live count starts afresh.
    func setDetectorModel(_ newModel: DetectorModel) {
        guard !modelLocked, newModel != detectorModel else { return }
        detectorModel = newModel
        analysisQueue.async { [weak self] in
            self?.live.setModel(newModel)
            self?.lastCountInfo = LiveCountInfo()
            DispatchQueue.main.async { self?.countInfo = LiveCountInfo() }
        }
    }

    func setCropsToEyepiece(_ crops: Bool) {
        analysisQueue.async { [weak self] in self?.live.cropsToEyepiece = crops }
    }

    func setMinimumConfidence(_ confidence: Float) {
        analysisQueue.async { [weak self] in self?.live.minimumConfidence = confidence }
    }

    /// Ends the run now, or after the current column; or takes "after" back. Each is a CSV
    /// event and the next guide update shows the answer.
    func endRun(_ action: EndRunAction) {
        endActionCount += 1
        analysisQueue.async { [weak self] in
            guard let self, self.guideEnabled else { return }
            switch action {
            case .now:
                self.dryRun.endNow()
                self.pendingEventName = "end_now"
            case .afterColumn:
                self.dryRun.endAfterColumn()
                self.pendingEventName = self.dryRun.isFinished ? "end_now" : "end_after_column"
            case .cancel:
                self.dryRun.cancelEnd()
                self.pendingEventName = "end_cancelled"
            }
        }
    }

    /// Closes the summary card.
    func dismissSummary() { runSummary = nil }

    /// The preview's own axes and sizes for the guide overlay (nil without a preview).
    /// Changing the direction of the axes or the size of a field in frame pixels starts the dry
    /// run afresh; showing the picture larger or shifted (centring) does not.
    func setGuideGeometry(_ geometry: GuideScreenGeometry?) {
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let old = self.dryRun.geometry
            self.dryRun.geometry = geometry
            let same: Bool
            switch (old, geometry) {
            case (nil, nil): same = true
            case (let old?, let geometry?): same = old.givesSamePositions(as: geometry)
            default: same = false
            }
            if !same { self.resetGuide() }
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
        runMarked = true
        analysisQueue.async { [weak self] in
            guard let self else { return }
            // The counting model opens now, not at column 1's first spot.
            self.live.prepare()
            self.pendingMark.place(PendingMark(name: "start", millimetres: nil))
            self.setup.rearmMonitor()
            self.pipeline.setStartPicture()
            // The knob rule says the X knob moves the picture left and right. A measured X
            // axis nearer vertical means that is not so on this microscope: say so once.
            if let axes = self.setup.stageAxes, KnobRule.xAxisIsVertical(axes.xDirection) {
                self.pendingEventName = "knob_axis_mismatch"
            }
            self.indicators.markStart(at: self.latestPositionFields)
            self.startTrailPoint = self.latestPositionFields
        }
    }

    /// "Stage straightened ✓ (tilt 9.6°)" for a moment when setup ends, with the real number.
    private static func stageToast(_ axes: StageAxes) -> String {
        axes == .identity
            ? "Stage not measured" : String(format: "Stage straightened ✓ (tilt %.1f°)", axes.tiltDegrees)
    }

    /// Shows `text` for a moment, as a mark does but never "(not logging)". Main queue only.
    private func showSetupToast(_ text: String) {
        markToast = text
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self?.markToast = nil
        }
    }

    /// Confirms a mark on screen for a moment. A mark made while no log is running is not
    /// written anywhere, and the toast says so. Main queue only.
    func showToast(_ text: String) {
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
            // Every visit starts the setup: align, focus, then the field.
            self.analysisQueue.async {
                self.frameCount = 0
                self.beginSetup()
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
        applyCameraRate(sessionCameraRate, to: device)

        // Fixed focus: autofocus hunts on a microscope. The user moves the lens by hand.
        if device.isFocusModeSupported(.locked), (try? device.lockForConfiguration()) != nil {
            device.setFocusModeLocked(
                lensPosition: ScanEngine.defaultLensPosition, completionHandler: nil)
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

    /// Sets the camera's frame rate and the exposure cap for `rate`, or puts both back for 30 fps.
    /// A device whose active format cannot do 20 fps is left as it is, and `cameraNote` says why.
    /// Session queue.
    private func applyCameraRate(_ rate: CameraRate, to device: AVCaptureDevice) {
        func note(_ text: String) {
            print("CAMERA \(text)")
            DispatchQueue.main.async { [weak self] in self?.cameraNote = text }
        }
        guard (try? device.lockForConfiguration()) != nil else {
            note("The camera could not be configured; left as it is.")
            return
        }
        defer { device.unlockForConfiguration() }
        // Runs first (defers go backwards), still locked: what the device ended up with.
        defer { reportCameraConfig("set", device: device, rate: rate) }
        guard let duration = rate.frameDuration, let fps = rate.framesPerSecond else {
            // 30 fps restores today's settings: the camera's own frame durations, no cap.
            device.activeVideoMinFrameDuration = .invalid
            device.activeVideoMaxFrameDuration = .invalid
            // .invalid is Apple's documented reset of the cap to the default; the format's
            // maximum would allow long exposures that lower the frame rate in dim light.
            device.activeMaxExposureDuration = .invalid
            note("")
            return
        }
        let supported = device.activeFormat.videoSupportedFrameRateRanges.contains {
            $0.minFrameRate <= Double(fps) && Double(fps) <= $0.maxFrameRate
        }
        guard supported else {
            note("The active camera format does not do \(fps) fps; left at its own rate.")
            return
        }
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        // After the frame durations: changing them resets the exposure cap.
        let cap = CMTime(
            seconds: CameraRateThresholds().maxExposureSeconds, preferredTimescale: 1_000_000)
        let format = device.activeFormat
        if cap >= format.minExposureDuration, cap <= format.maxExposureDuration {
            device.activeMaxExposureDuration = cap
            note("20 fps, exposure capped at 1/30 s.")
        } else {
            note("20 fps; the exposure cap is outside what this format allows, so not set.")
        }
    }

    /// What the camera is actually doing, to find out why 20 fps reads 16: the frame durations,
    /// the exposure cap, the active format's rate ranges and the session preset. Console now; the
    /// CSV gets it once on the next logged row, and the first frame after it reports again
    /// ("running") in case a later configuration reset something. Any queue.
    private func reportCameraConfig(_ stage: String, device: AVCaptureDevice, rate: CameraRate) {
        func seconds(_ time: CMTime) -> String {
            time.isValid ? String(format: "%.4f", time.seconds) : "invalid"
        }
        let ranges = device.activeFormat.videoSupportedFrameRateRanges
            .map { String(format: "%.0f-%.0f", $0.minFrameRate, $0.maxFrameRate) }
            .joined(separator: "|")
        // No commas or quotes: the text goes into one CSV field as it is.
        let text =
            "\(stage) rate=\(rate.rawValue) min_dur=\(seconds(device.activeVideoMinFrameDuration))"
            + " max_dur=\(seconds(device.activeVideoMaxFrameDuration))"
            + " max_exposure=\(seconds(device.activeMaxExposureDuration)) ranges=\(ranges)"
            + " preset=\(session.sessionPreset.rawValue)"
        print("CAMERA CONFIG \(text)")
        analysisQueue.async { [weak self] in
            guard let self else { return }
            self.cameraConfigText = text
            self.cameraConfigPending = true
            if stage == "set" { self.reportsRunningConfig = true }
        }
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.cameraError = message }
    }

    // MARK: Row building

    func row(
        from step: SlideMovementStep, indicators: MovementIndicators, seconds: Double,
        label: String, mark: String, millimetres: Double?, test: SlideLabTest, note: String,
        guide: GuideRowFields? = nil, monitor: RunMonitorInfo? = nil
    ) -> MovementLogRow {
        var logged = MovementLogRow(
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
            guideCaptures: guide?.captures, guideAxesMapping: guide?.axesMapping ?? "",
            boxSharpLeft: step.tracking.halfSharpness?.left,
            boxSharpRight: step.tracking.halfSharpness?.right,
            boxSharpTop: step.tracking.halfSharpness?.top,
            boxSharpBottom: step.tracking.halfSharpness?.bottom,
            focusLeft: step.tracking.halfFocusRatio?.left,
            focusRight: step.tracking.halfFocusRatio?.right,
            focusTop: step.tracking.halfFocusRatio?.top,
            focusBottom: step.tracking.halfFocusRatio?.bottom,
            edgeCandidate: guide?.edgeCandidate ?? "", edgeVerdict: guide?.edgeVerdict ?? "",
            edgeReason: guide?.edgeReason ?? "", boxSharpSideA: guide?.sideSharpA,
            boxSharpSideB: guide?.sideSharpB)
        logged.monitorState = monitor?.state.csvName ?? ""
        logged.focusIndex = monitor?.focusIndex
        logged.focusBaseline = monitor?.focusBaseline
        logged.circleShiftR = monitor?.circleShift
        logged.circleRadiusChange = monitor?.circleRadiusChange
        logged.focusLow = monitor.map { $0.focusLow } ?? false
        logged.sharpnessRef = monitor?.sharpnessReference
        logged.sharpnessShare = monitor?.sharpnessShare
        logged.pauseCause = monitor?.pauseCause ?? ""
        logged.focusDialOffset = monitor?.dial?.offset
        logged.focusDialSide = monitor?.dial?.csvSide ?? ""
        logged.quadAheadAway = guide?.quadAheadAway
        logged.quadAheadToward = guide?.quadAheadToward
        logged.quadBehindAway = guide?.quadBehindAway
        logged.quadBehindToward = guide?.quadBehindToward
        logged.cornerBoxShare = guide?.cornerBoxShare
        logged.chainX = step.tracking.chain.map { Double($0.x) }
        logged.chainY = step.tracking.chain.map { Double($0.y) }
        logged.anchorChainGap = step.tracking.anchorChainGap
        logged.lineState = guide?.lineState ?? ""
        logged.lineAttachedCount = guide?.lineAttachedCount ?? 0
        logged.edgeMode = guide?.edgeMode ?? ""
        logged.lineAccept = guide?.lineAccept ?? ""
        logged.areaAheadShare = guide?.areaAheadShare
        logged.predictedEdgeAlong = guide?.predictedEdgeAlong
        logged.expectedEdgeAsk = guide?.expectedEdgeAsk ?? false
        logged.sparseSkips = step.tracking.sparseSkips
        logged.edgeFeedback = guide?.edgeFeedback ?? ""
        logged.spotMode = guide?.spotMode ?? ""
        logged.spotWindow = guide?.spotWindow ?? ""
        logged.touchSeconds = guide?.touchSeconds
        logged.missedSpots = guide?.missedSpots
        logged.coverageStep = guide.map { $0.coverageStep }
        logged.countingActive = guide?.countingActive ?? false
        logged.ghostFrames = step.tracking.ghostFrames
        logged.ghostFallbacks = step.tracking.ghostFallbacks
        logged.featureCells = step.tracking.featureCells
        logged.featureQuarters = step.tracking.featureQuarters
        logged.sparseTracking = step.tracking.sparse
        logged.focusStillOnset = monitor.map { $0.focusStillOnset } ?? false
        return logged
    }

    /// The route has finished, for any reason: writes the run record (JSON, in the Files app)
    /// and the summary row of the CSV, and shows the summary card. Analysis queue only.
    private func finalizeRun(seconds: Double) {
        let spots = dryRun.spotsTicked
        let elapsed = seconds - runStartSeconds
        let reason = dryRun.finishReason ?? .endedByHelper
        live.drain()
        let options = live.detectorOptions
        let record = GuideRunRecord(
            started: runStartedAt ?? .now, ended: .now, finishReason: reason,
            spotMode: dryRun.spotMode == .briefTouch ? "brief_touch" : "hold_still",
            coverageStep: dryRun.coverageStep, columns: dryRun.column, spotsTicked: spots,
            missedSpots: dryRun.missedSpots, elapsedSeconds: elapsed,
            secondsPerSpot: spots > 0 ? elapsed / Double(spots) : nil,
            coverageShare: GuideRunRecord.coverageShare(
                columns: dryRun.column, step: dryRun.coverageStep,
                edgeSpanFields: dryRun.edgeSpanFields),
            countsByLabel: live.counter.helperCountByLabel,
            tallyCountsByLabel: live.counter.tallyCountByLabel,
            totalCount: live.counter.helperTotal, minimumConfidence: Double(options.confidence),
            cropToEyepiece: options.crop, classNames: options.classes,
            framesCounted: live.counter.framesCounted,
            framesSkippedByReason: live.counter.framesSkippedByReason,
            detectorModel: live.model.rawValue, discDrops: live.counter.discDrops,
            bigDrops: live.counter.bigDrops, detectorUnits: live.units.rawValue,
            rightEdgeSource: dryRun.rightEdgeSource, sideInsetFields: dryRun.sideInsetFields,
            organisms: live.counter.map.entries.map {
                RunMapOrganism(
                    label: $0.label, x: Double($0.fields.x), y: Double($0.fields.y),
                    column: $0.column, seconds: $0.firstSeenSeconds)
            },
            path: RunMapContent.thinned(runPath), edges: runMapEdges(),
            mapMapping: dryRun.mapping.rawValue, mapMirrored: dryRun.mirrored)
        var items: [URL] = []
        if let json = Self.writeRun(record) { items.append(json) }
        if logging, var last = rows.last {
            last.event = "summary"
            last.eventDetail =
                "\(record.title); \(record.totalCount) organisms; \(record.columns) columns; \(spots) spots"
            rows.append(last)
            if let csv = Self.write(rows, test: currentTest) { items.append(csv) }
        }
        DispatchQueue.main.async { [weak self] in
            // The map as a picture, shared with the JSON and the CSV.
            if let data = RunMapExport.pngData(for: record), let png = Self.writeMapPNG(data) {
                items.append(png)
            }
            self?.runSummary = record
            self?.summaryItems = items
            self?.runMarked = false
        }
    }

    /// The run's edges for its record: the lines and the confirmed points, in the trail's space.
    private func runMapEdges() -> [RunMapEdge] {
        guidePredicted.map {
            RunMapEdge(
                kind: String(describing: $0.kind), x1: Double($0.from.x), y1: Double($0.from.y),
                x2: Double($0.to.x), y2: Double($0.to.y))
        }
            + guideEdgePoints.map {
                RunMapEdge(
                    kind: "point", x1: Double($0.x), y1: Double($0.y), x2: Double($0.x),
                    y2: Double($0.y))
            }
    }

    /// Documents/SlideLab/Runs/run-<timestamp>-map.png, next to the run's JSON.
    private static func writeMapPNG(_ data: Data) -> URL? {
        let folder = DetectionSnapshotWriter.documents.appending(path: "SlideLab/Runs")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "run-\(stamp())-map.png")
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// Documents/SlideLab/Runs/run-<timestamp>.json, which the Files app shows.
    private static func writeRun(_ record: GuideRunRecord) -> URL? {
        let folder = DetectionSnapshotWriter.documents.appending(path: "SlideLab/Runs")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: "run-\(stamp()).json")
            try GuideRunRecord.encoder().encode(record).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    static func write(_ rows: [MovementLogRow], test: SlideLabTest) -> URL? {
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

}

// MARK: - Frame analysis

extension ScanEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    /// The output dropped a frame (`alwaysDiscardsLateVideoFrames`): counted when it was late,
    /// the analysis still busy with the one before. Delegate queue (the analysis queue).
    func captureOutput(
        _ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let reason = CMGetAttachment(
            sampleBuffer, key: kCMSampleBufferAttachmentKey_DroppedFrameReason, attachmentModeOut: nil)
        if (reason as? String) == (kCMSampleBufferDroppedFrameReason_FrameWasLate as String) {
            lateFrameDrops += 1
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        if reportsRunningConfig, let device {
            reportsRunningConfig = false
            reportCameraConfig("running", device: device, rate: sessionCameraRate)
        }
        // The camera's own rate, from the capture timestamps of the last second.
        let captured = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        frameTimes.append(captured)
        frameTimes.removeAll { captured - $0 > 1 }
        guard analyzing, frameCount % analyzeEveryNthFrame == 0,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else { return }
        let time = captured
        lastFrameSeconds = time
        guard
            let output = setup.process(
                buffer, seconds: time, pipeline: pipeline,
                measureAgreement: logging && measureAgreementEnabled,
                guidePosition: { [dryRun] in dryRun.guidePosition(for: $0) },
                viewClass: guideEnabled ? dryRun.lastViewClass : .blank,
                isStill: indicators.stillSeconds > 0, stillSeconds: indicators.stillSeconds)
        else { return }
        let stepChanged = setup.step != lastPublishedStep
        if stepChanged {
            // Reaching field starts learning, which needs a clean display.
            lastPublishedStep = setup.step
            clearTrackingDisplay()
            // The run starts clean: the stage's axes are in, so the guide's positions are.
            if setup.step == .done { resetGuide() }
        }
        let step: SlideMovementStep
        switch output {
        case .setup(let info):
            publishSetup(info, time: time, force: stepChanged)
            return
        case .tracked(let tracked):
            step = tracked
            if stepChanged {
                let info = setup.info
                let toast =
                    setup.step == .done
                    ? setup.stageAxes.map { Self.stageToast($0) } : nil
                DispatchQueue.main.async { [weak self] in
                    self?.setupInfo = info
                    if let toast { self?.showSetupToast(toast) }
                }
            }
        }

        if let handler = guideSampleHandler, setup.step == .stage || setup.step == .done {
            let sample = (dryRun.guidePosition(for: step), step.tracking.trackingState)
            DispatchQueue.main.async { handler(sample.0, sample.1, time) }
        }
        if let image = step.thumbnail { thumbnailThrottle.offer(image) }
        latestPositionFields = step.positionFields
        indicators.update(
            shake: step.shake, anchorOffset: step.usedOffset,
            positionFields: step.positionFields, isLost: step.isLost, event: step.event,
            referenceSide: step.boxSide, seconds: time, hopDistance: step.hopLimit,
            hasDetail: step.hasDetail)
        // The speed bar and the status banner are steered by: full rate, when they change.
        if indicators.speedFraction != lastSpeed.fraction || indicators.status != lastSpeed.status {
            lastSpeed = (indicators.speedFraction, indicators.status)
            let speed = indicators.speedFraction
            let status = indicators.status
            DispatchQueue.main.async { [speedState] in
                speedState.speedFraction = speed
                speedState.status = status
            }
        }
        var edgeLine: EdgeLine?
        var countLog = LiveCountFrameLog()
        if guideEnabled, setup.step == .done {
            dryRun.pauseReason =
                pausesOnMonitorFlag ? setup.monitorState.pauseReason : nil
            dryRun.focusLow = pausesOnMonitorFlag && setup.isFocusLow
            // The line is measured first so the guide can use it on this very reading.
            edgeLine = edgeProbe.update(buffer, step: step, direction: dryRun.frameHeading)
            let result = dryRun.update(
                step: step, indicators: indicators, seconds: time, edgeLine: edgeLine)
            latestGuide = result.fields
            if runStartedAt == nil {
                runStartedAt = Date()
                runStartSeconds = time
                live.prepare()
            }
            if dryRun.countingActive != lastCountingActive {
                lastCountingActive = dryRun.countingActive
                live.setCounting(lastCountingActive)
            }
            lastCountFrameSize = step.frameSize
            if dryRun.countingActive {
                let reason = LiveOrganismCounter.skipReason(
                    tracking: step.tracking.trackingState,
                    isGhostOrSparseSkip: step.reading == "ghost" || step.reading == "sparse_skip",
                    monitorPaused: dryRun.pauseReason != nil, viewClass: dryRun.lastViewClass,
                    speedFraction: indicators.speedFraction,
                    stillSeconds: indicators.stillSeconds,
                    secondsSinceLastDetection: live.secondsSinceDetection(
                        at: time - runStartSeconds))
                countLog = live.process(
                    buffer: buffer, skipReason: reason,
                    pictureMoved: LiveOrganismCounter.pictureMoved(
                        frameShift: step.tracking.frameShift),
                    trackerPosition: step.position, frameSize: step.frameSize,
                    fieldCircle: step.fieldState?.mask.flatMap { FieldCircle(fitting: $0) },
                    seconds: time - runStartSeconds, column: dryRun.column,
                    fieldSide: step.boxSide)
            }
            publishCount(isActive: dryRun.countingActive, frameSize: step.frameSize)
            let path = edgeLine.map { $0.isCandidate ? $0.path : [] }
            let lineState = dryRun.lineState
            DispatchQueue.main.async { [edgeLineState] in
                if let path { edgeLineState.update(path) }
                edgeLineState.setLineState(lineState)
            }
            latestGuideInfo = result.info
            if let point = result.captureTrailPoint { guideCaptured.append(point) }
            guideTarget = result.targetTrailPoint
            guidePredicted = result.predictedTrailLines
            guideEdgePoints = result.edgeTrailPoints
            let control = SlideMovementInfo.RunControl(
                pendingEnd: dryRun.pendingEnd, columnInProgress: dryRun.columnInProgress,
                isFinished: dryRun.isFinished)
            if control != lastRunControl {
                lastRunControl = control
                DispatchQueue.main.async { [weak self] in self?.runControl = control }
            }
            let overlay = result.overlay
            let captureCount = result.info.captureCount
            // Also the question "Edge should be here. Confirm?": always the helper's call.
            let asks =
                (dryRun.asksEdges && result.fields.lineAtCross) || result.fields.expectedEdgeAsk
            let canMark = result.fields.canMarkEdge
            // The question on the card: raised while the guide asks, kept (with what it was about)
            // for a few seconds after, and closed when the route settled the edge itself.
            edgeQuestions.update(
                asking: asks, snapshot: asks ? dryRun.edgeQuestionSnapshot : nil, seconds: time)
            if result.info.edgeReachedCount != lastEdgeReachedCount {
                lastEdgeReachedCount = result.info.edgeReachedCount
                edgeQuestions.close()
            }
            let questionID = edgeQuestions.currentID
            DispatchQueue.main.async { [weak self] in
                self?.overlayState.update(
                    model: overlay, captureCount: captureCount, asksEdge: asks,
                    canMarkEdge: canMark, questionID: questionID)
            }
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
        if guideEnabled, !dryRun.isFinished {
            runPath.append(step.positionFields)
            // Keeps every other point when it gets long: the path stays whole and small.
            if runPath.count > 4 * RunMapContent.maxPathPoints {
                runPath = runPath.enumerated().filter { $0.offset % 2 == 0 }.map(\.element)
            }
        }
        trailBlind.append(!step.hasDetail)
        if trail.count > trailLength {
            trail.removeFirst(trail.count - trailLength)
            trailBlind.removeFirst(trailBlind.count - trailLength)
        }

        if logging {
            let origin = logOrigin ?? time
            logOrigin = origin
            let mark = pendingMark.take()
            var logged = row(
                from: step, indicators: indicators, seconds: time - origin,
                label: currentLabel, mark: mark?.name ?? "",
                millimetres: mark?.millimetres, test: currentTest, note: currentNote,
                guide: guideEnabled ? latestGuide : nil,
                monitor: setup.step == .done ? setup.info.monitor : nil)
            logged.edgeLine = edgeLine
            var automatic = false
            if guideEnabled {
                automatic = snapshotTrigger.update(
                    edgeReason: logged.edgeReason, edgeVerdict: logged.edgeVerdict,
                    instruction: logged.guideInstruction, lineCandidate: edgeLine?.isCandidate)
            }
            let tapped = pendingEdgeFeedback
            if tapped != nil || automatic || snapshotRequested {
                logged.snapshot =
                    snapshots.save(
                        buffer, csvSeconds: time - origin,
                        automatic: tapped == nil && !snapshotRequested, tap: tapped != nil)
                    ?? ""
            }
            snapshotRequested = false
            if let tapped {
                logged.edgeFeedback = tapped.csvName
                pendingEventName = "edge_user_\(tapped.csvName)"
            } else if logged.edgeFeedback == "auto" {
                pendingEventName = pendingEventName.isEmpty ? "edge_auto" : pendingEventName
            }
            pendingEdgeFeedback = nil
            // This frame's own skip reason, and the oldest result that arrived since the last
            // row (from an earlier frame: det_frame_seconds says which), each written once.
            let result = countLog.active ? live.takeCompleted() : nil
            logged.detSkipReason = countLog.skipReason
            logged.detRan = result?.ran ?? false
            logged.detMilliseconds = result?.milliseconds
            logged.detFound = result?.found
            logged.detOutside = result?.outside
            logged.detNewTally = result?.newInTally
            logged.detNewMap = result?.newOnMap
            logged.detRepeatMap = result?.repeatOnMap
            logged.countTallyTotal = result?.tallyTotal ?? countLog.tallyTotal
            logged.countMapTotal = result?.mapTotal ?? countLog.mapTotal
            logged.detectorModel = countLog.model.isEmpty ? live.model.rawValue : countLog.model
            logged.detDropDisc = result?.droppedDisc
            logged.detDropBig = result?.droppedBig
            logged.detUnits = countLog.units
            logged.detFrameSeconds = result?.frameSeconds
            logged.detPreMs = result?.preMilliseconds
            logged.detInferMs = result?.inferMilliseconds
            logged.detDecodeMs = result?.decodeMilliseconds
            logged.frameDt = indicators.frameGap
            logged.cameraFps = Double(frameTimes.count)
            logged.cameraDrops = lateFrameDrops
            logged.knobWords = helperWords
            logged.exposureMs = device.map { $0.exposureDuration.seconds * 1000 }
            logged.iso = device.map { Double($0.iso) }
            logged.thermalState = LabDeviceStatus.thermalName
            logged.batteryLevel = deviceStatus.batteryLevel
            if let counted = result?.counted, !counted.isEmpty {
                logged.eventDetail = counted.joined(separator: "; ")
                if pendingEventName.isEmpty { pendingEventName = "organism_counted" }
            }
            // Once per run: how far the first and last columns sit inside the side edges.
            if !sideInsetLogged, let inset = dryRun.sideInsetFields, logged.eventDetail.isEmpty,
                pendingEventName.isEmpty
            {
                sideInsetLogged = true
                pendingEventName = "side_inset"
                logged.eventDetail = String(format: "side_inset_fields=%.2f", inset)
            }
            if let id = pendingEdgeQuestionID {
                logged.eventDetail =
                    (logged.eventDetail.isEmpty ? "" : logged.eventDetail + "; ") + "question=\(id)"
                pendingEdgeQuestionID = nil
            }
            if cameraConfigPending, logged.eventDetail.isEmpty, pendingEventName.isEmpty {
                cameraConfigPending = false
                pendingEventName = "camera_config"
                logged.eventDetail = cameraConfigText
            }
            if !pendingEventName.isEmpty { logged.event = pendingEventName }
            rows.append(logged)
            onRowLogged?(logged, time)
        }
        pendingEventName = ""
        if guideEnabled, dryRun.isFinished, !runFinalized {
            runFinalized = true
            finalizeRun(seconds: time)
        }

        publishHaptics()
        publish(step, time: time)
    }

    /// Publishes the count when it changed, through the throttle. Analysis queue. Called for
    /// every analysed frame, and when the detector queue finishes a result.
    private func publishCount(isActive: Bool, frameSize: CGSize) {
        let info = live.info(isActive: isActive, frameSize: frameSize)
        guard info != lastCountInfo else { return }
        lastCountInfo = info
        countThrottle.offer(info)
        if showsDetectionsFlag {
            DispatchQueue.main.async { [weak self] in self?.liveBoxes = info }
        }
    }

    /// A detection finished on the detector queue: the count and the haptics follow at once.
    private func detectionFinished() {
        analysisQueue.async { [weak self] in
            guard let self, self.guideEnabled, self.setup.step == .done else { return }
            self.publishCount(
                isActive: self.lastCountingActive, frameSize: self.lastCountFrameSize)
            self.publishHaptics()
        }
    }

    /// What the haptics watch, at full rate: pushed when one of them changes.
    private func publishHaptics() {
        var current = SlideMovementInfo.Haptics()
        current.hops = hopCount
        current.lost = lostCount
        current.captures = latestGuideInfo.captureCount
        current.edges = latestGuideInfo.edgeCount
        current.wrongWays = latestGuideInfo.wrongWayCount
        current.nudges = latestGuideInfo.nudgeCount
        current.edgesReached = latestGuideInfo.edgeReachedCount
        current.stageLimits = latestGuideInfo.stageLimitCount
        current.organisms = lastCountInfo.hapticCount
        current.monitor = setup.info.monitor.state
        current.stopReached =
            currentTest == .stops && indicators.stillSeconds >= slideLabStillGoalSeconds
        guard current != lastHaptics else { return }
        lastHaptics = current
        DispatchQueue.main.async { [weak self] in self?.hapticInfo = current }
    }

    /// Hands the screen the setup's state through the throttle (at once on a change of step),
    /// and the focus meter's value on every frame.
    private func publishSetup(_ info: LabSetupInfo, time: Double, force: Bool) {
        let focus = info.focus
        let dial = info.focusDial
        DispatchQueue.main.async { [weak self] in self?.focusMeter.update(focus, dial: dial) }
        setupThrottle.offer(info, force: force)
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
            hopCount: hopCount, blind: trailBlind,
            guideCaptured: guideEnabled ? guideCaptured : [],
            guideTarget: guideEnabled ? guideTarget : nil,
            predicted: guideEnabled ? guidePredicted : [],
            edgePoints: guideEnabled && showsLifeOnMap ? guideEdgePoints : [],
            life: guideEnabled && showsLifeOnMap ? lastCountInfo.dots : [])
        let circle =
            step.awaitingReview ? step.fieldState?.mask.flatMap { FieldCircle(fitting: $0) } : nil
        let fieldInfo = SlideMovementInfo.Field(
            state: step.fieldState,
            registrationRect: step.registrationRect, frameSize: step.frameSize,
            awaitingReview: step.awaitingReview, circle: circle)
        let count = rows.count
        let isLogging = logging
        panelThrottle.offer(
            PanelUpdate(
                setup: setup.info, status: status, readouts: readouts, trail: trailInfo,
                field: fieldInfo, guide: guideInfo, rowCount: count, isLogging: isLogging,
                thermal: LabDeviceStatus.thermalName))
    }
}
