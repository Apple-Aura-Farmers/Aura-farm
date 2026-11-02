import AVFoundation
import Observation

/// Runs the camera, analyzes live frames, and publishes the quality state for the UI.
/// Frames arrive on a background queue; UI state is only changed on the main queue.
@Observable
final class CameraQualityModel: NSObject {
    // MARK: UI state (main queue only)

    private(set) var authorization: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    private(set) var topIssue: CaptureIssue?
    private(set) var isReady = false
    private(set) var latestReading: CaptureQualityReading?
    private(set) var cameraError: String?
    private(set) var lensPosition = CameraQualityModel.defaultLensPosition
    /// What the helper should be doing in the sweep: hold still, move the slide left, or done.
    private(set) var sweepPrompt: SweepPrompt = .move(.right, kept: 0, of: SweepThresholds().framesPerSweep)
    /// How far along the sweep is, for the progress the helper watches.
    private(set) var sweepProgress = FrameSweep().progress
    /// How many organisms have been counted in this sweep, and of what.
    private(set) var countedTotal = 0
    private(set) var countByLabel: [String: Int] = [:]
    /// What to outline on the preview right now.
    private(set) var countedBoxes: [CountedBox] = []
    /// Why nothing is being counted, if the detector could not be opened. Counting failing
    /// does not stop a sweep: the frames are still worth having.
    private(set) var countingProblem: String?

    // MARK: Camera

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored let recorder = FrameSetRecorder()
    @ObservationIgnored private let sessionQueue = DispatchQueue(label: "camera.session")
    @ObservationIgnored private let analysisQueue = DispatchQueue(label: "camera.analysis")
    @ObservationIgnored private var isConfigured = false
    @ObservationIgnored private var device: AVCaptureDevice?

    // MARK: Analysis (analysis queue only)

    @ObservationIgnored private let monitor = CaptureQualityMonitor()
    @ObservationIgnored private let shakeEstimator = ShakeEstimator()
    @ObservationIgnored private var frameCount = 0
    /// Analyze every Nth frame: about 10 fps at 30 fps capture.
    @ObservationIgnored private let analyzeEveryNthFrame = 3
    @ObservationIgnored private let sweep = FrameSweep()
    /// Analysis queue only: whether frames are being kept right now.
    @ObservationIgnored private var sweepActive = false
    /// Opened when the first sweep starts, and kept: opening it costs about a fifth of a
    /// second on the GPU.
    @ObservationIgnored private var detector: Detector?
    @ObservationIgnored private var tally = OrganismTally()

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

    func stop() {
        endSweep()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Starts keeping frames. Each frame is kept once the image is good and still; between
    /// frames the helper is asked to move the slide to the left.
    func startSweep(details: RecordingMetadata) {
        analysisQueue.async { [weak self] in
            guard let self, !self.sweepActive else { return }
            self.sweep.reset()
            self.tally.reset()
            self.openDetector()
            guard self.recorder.begin(details: details) else { return }
            self.sweepActive = true
            self.publishPrompt(self.sweep.prompt, self.sweep.progress)
            self.publishCount()
        }
    }

    /// Ends the sweep early. The frames already written are kept and their manifest is saved.
    func endSweep() {
        analysisQueue.async { [weak self] in
            guard let self, self.sweepActive else { return }
            self.sweepActive = false
            self.recorder.finish(stoppedEarly: !self.sweep.isFinished)
            self.clearBoxes()
        }
    }

    /// Where the lens sits when the camera starts. 0 is the closest focus, 1 the furthest.
    /// PLACEHOLDER: not calibrated for any microscope and lens. Find the value that focuses
    /// your setup with the focus slider, then set it here.
    static let defaultLensPosition: Float = 1.0

    /// Moves the lens. There is no autofocus: it hunts on a microscope, where the image only
    /// changes when the stage moves.
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

    private func runSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured { self.configureSession() }
            guard self.isConfigured else { return }

            self.analysisQueue.async {
                self.monitor.reset()
                self.shakeEstimator.reset()
                self.frameCount = 0
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
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
            device.setFocusModeLocked(lensPosition: Self.defaultLensPosition, completionHandler: nil)
            device.unlockForConfiguration()
        }

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
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

    private func publishPrompt(_ prompt: SweepPrompt, _ progress: SweepProgress) {
        DispatchQueue.main.async { [weak self] in
            self?.sweepPrompt = prompt
            self?.sweepProgress = progress
        }
    }

    // MARK: Counting (analysis queue only)

    /// Opens the detector the first time a sweep starts. The GPU rather than the Neural
    /// Engine: measured on an iPhone 17, one frame took 5.1 ms there against 8.6 ms on the
    /// Neural Engine, and the model opened in 226 ms against 1092 ms. What that costs in
    /// battery over a long sweep has not been measured.
    private func openDetector() {
        guard detector == nil else { return }
        do {
            detector = try Detector(computeUnits: .cpuAndGPU)
        } catch {
            let message = error.localizedDescription
            DispatchQueue.main.async { [weak self] in self?.countingProblem = message }
        }
    }

    /// Runs the detector on one frame and folds what it finds into the tally.
    ///
    /// Vision gives boxes as a share of the frame with the origin at the bottom left. The
    /// tally works in pixels from the top left, the same way round as the shift it is given,
    /// and the preview wants shares from the top left, so both conversions happen here.
    private func count(in buffer: CVPixelBuffer) {
        guard let detector else { return }
        let width = Double(CVPixelBufferGetWidth(buffer))
        let height = Double(CVPixelBufferGetHeight(buffer))
        guard let detections = try? detector.detections(in: buffer) else { return }

        tally.update(
            found: detections.map { detection in
                OrganismTally.Found(
                    label: detection.label,
                    box: CGRect(
                        x: detection.box.minX * width,
                        y: (1 - detection.box.maxY) * height,
                        width: detection.box.width * width,
                        height: detection.box.height * height
                    ),
                    confidence: detection.confidence
                )
            },
            pictureMoved: shakeEstimator.lastShift ?? .zero
        )
        publishCount(frameWidth: width, frameHeight: height)
    }

    /// The sweep is over, so nothing is outlined any more. The count stays on screen.
    private func clearBoxes() {
        DispatchQueue.main.async { [weak self] in self?.countedBoxes = [] }
    }

    private func publishCount(frameWidth: Double = 1, frameHeight: Double = 1) {
        let total = tally.total
        let byLabel = tally.countByLabel
        let boxes = tally.visible.map { track in
            CountedBox(
                id: track.id,
                label: track.label,
                box: CGRect(
                    x: track.box.minX / frameWidth,
                    y: track.box.minY / frameHeight,
                    width: track.box.width / frameWidth,
                    height: track.box.height / frameHeight
                )
            )
        }
        DispatchQueue.main.async { [weak self] in
            self?.countedTotal = total
            self?.countByLabel = byLabel
            self?.countedBoxes = boxes
        }
    }
}

// MARK: - Frame analysis

extension CameraQualityModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        frameCount += 1
        guard frameCount % analyzeEveryNthFrame == 0,
            let buffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let stats = FrameAnalyzer.brightnessAndSharpness(of: buffer)
        else { return }

        let reading = CaptureQualityReading(
            brightness: stats.brightness,
            sharpness: stats.sharpness,
            shakePixels: shakeEstimator.update(with: buffer)
        )
        monitor.update(with: reading)

        let top = monitor.topIssue
        let ready = monitor.isReady
        let settled = monitor.hasSettled
        DispatchQueue.main.async { [weak self] in
            self?.latestReading = reading
            self?.topIssue = top
            self?.isReady = ready
        }

        guard sweepActive else { return }
        // Counting runs on every analyzed frame, not only on the ones kept: a frame that is
        // not kept still shows ground the slide is passing over, and the tally needs to see
        // it to follow what is already counted across the gap.
        count(in: buffer)
        // Shake is not passed as a blocker: a sweep is the slide moving, so the sweep
        // decides for itself which issues stop a frame being kept.
        let step = sweep.update(isSettled: settled, issue: top, shift: shakeEstimator.lastShift)
        if step == .keepFrame, let bytes = recorder.write(buffer) {
            sweep.addWrittenBytes(bytes)
        }
        publishPrompt(sweep.prompt, sweep.progress)
        if sweep.isFinished {
            sweepActive = false
            recorder.finish(stoppedEarly: sweep.bytesWritten >= sweep.thresholds.maxBytes)
            clearBoxes()
        }
    }
}
