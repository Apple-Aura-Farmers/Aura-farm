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

    // MARK: Camera

    @ObservationIgnored let session = AVCaptureSession()
    @ObservationIgnored let recorder = ClipRecorder()
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
        recorder.stop()
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
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
                  (try? device.lockForConfiguration()) != nil else { return }
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
              session.canAddInput(input) else {
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

        guard session.canAddOutput(recorder.output) else {
            publishError("Recording could not be set up.")
            return
        }
        session.addOutput(recorder.output)
        // The app is portrait only; 90 degrees writes clips the way the user sees them.
        if let connection = recorder.output.connection(with: .video),
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        isConfigured = true
    }

    private func publishError(_ message: String) {
        DispatchQueue.main.async { [weak self] in self?.cameraError = message }
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
              let stats = FrameAnalyzer.brightnessAndSharpness(of: buffer) else { return }

        let reading = CaptureQualityReading(
            brightness: stats.brightness,
            sharpness: stats.sharpness,
            shakePixels: shakeEstimator.update(with: buffer)
        )
        monitor.update(with: reading)

        let top = monitor.topIssue
        let ready = monitor.isReady
        DispatchQueue.main.async { [weak self] in
            self?.latestReading = reading
            self?.topIssue = top
            self?.isReady = ready
        }
    }
}
