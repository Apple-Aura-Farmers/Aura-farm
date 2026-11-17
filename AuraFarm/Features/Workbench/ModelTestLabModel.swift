#if DEBUG
    import AVFoundation
    import Observation

    /// The default camera and the detector, and nothing else: no setup, no tracker, no guide.
    /// For trying a model on whatever the phone is pointed at. Frames are detected on the analysis
    /// queue, one at a time (late frames are dropped); the screen's state changes on the main
    /// queue only. Debug builds only.
    @Observable
    final class ModelTestLabModel: NSObject {
        struct Found: Identifiable, Equatable {
            var id: Int
            var label: String
            var confidence: Float
        }

        // MARK: UI state (main queue only)

        private(set) var boxes: [CountedBox] = []
        private(set) var found: [Found] = []
        private(set) var milliseconds = 0.0
        private(set) var framesPerSecond = 0.0
        private(set) var loadMilliseconds: Double?
        private(set) var status = "Starting the camera…"
        private(set) var isLoading = false

        // MARK: Camera

        @ObservationIgnored let session = AVCaptureSession()
        @ObservationIgnored private let sessionQueue = DispatchQueue(label: "modeltest.session")
        @ObservationIgnored private let analysisQueue = DispatchQueue(label: "modeltest.analysis")
        @ObservationIgnored private let loadQueue = DispatchQueue(
            label: "modeltest.load", qos: .userInitiated)
        @ObservationIgnored private var isConfigured = false

        // MARK: Analysis (analysis queue only)

        @ObservationIgnored private var detector: OrganismDetector?
        @ObservationIgnored private var minimumConfidence = OrganismDetector.leastConfidence
        @ObservationIgnored private var cropsToCentre = false
        @ObservationIgnored private var lastFrameAt = 0.0
        @ObservationIgnored private var smoothedFps = 0.0

        // MARK: Lifecycle

        func start() {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                guard granted else {
                    DispatchQueue.main.async { self.status = "Camera access is off. Turn it on in Settings." }
                    return
                }
                self.sessionQueue.async {
                    if !self.isConfigured { self.configure() }
                    if !self.session.isRunning { self.session.startRunning() }
                }
            }
        }

        func stop() {
            sessionQueue.async { [weak self] in
                if self?.session.isRunning == true { self?.session.stopRunning() }
            }
        }

        private func configure() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .hd1280x720
            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
            else {
                DispatchQueue.main.async { self.status = "The camera could not be opened." }
                return
            }
            session.addInput(input)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: analysisQueue)
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            isConfigured = true
        }

        // MARK: Settings

        /// Opens `model` off the main and analysis queues; frames show no detections until it is
        /// ready. Reports how long it took to open.
        func setModel(_ model: DetectorModel) {
            isLoading = true
            status = "Opening \(model.displayName)…"
            loadQueue.async { [weak self] in
                let started = CFAbsoluteTimeGetCurrent()
                let opened = try? OrganismDetector(model: model, computeUnits: .cpuAndGPU)
                let took = (CFAbsoluteTimeGetCurrent() - started) * 1000
                self?.analysisQueue.async {
                    self?.detector = opened
                    DispatchQueue.main.async {
                        self?.isLoading = false
                        self?.loadMilliseconds = opened == nil ? nil : took
                        self?.status =
                            opened == nil
                            ? "\(model.displayName) is not in the app." : model.displayName
                        self?.boxes = []
                        self?.found = []
                    }
                }
            }
        }

        func setMinimumConfidence(_ confidence: Float) {
            analysisQueue.async { [weak self] in self?.minimumConfidence = confidence }
        }

        /// Shows the model only the middle square of the frame (the eyepiece's, roughly).
        func setCropsToCentre(_ crops: Bool) {
            analysisQueue.async { [weak self] in self?.cropsToCentre = crops }
        }
    }

    extension ModelTestLabModel: AVCaptureVideoDataOutputSampleBufferDelegate {
        func captureOutput(
            _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
            from connection: AVCaptureConnection
        ) {
            guard var detector, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            detector.minimumConfidence = minimumConfidence
            let width = CGFloat(CVPixelBufferGetWidth(buffer))
            let height = CGFloat(CVPixelBufferGetHeight(buffer))
            var crop: CGRect?
            if cropsToCentre {
                let side = min(width, height)
                crop = CGRect(x: (width - side) / 2, y: (height - side) / 2, width: side, height: side)
            }
            let started = CFAbsoluteTimeGetCurrent()
            let detections = (try? detector.detections(in: buffer, crop: crop)) ?? []
            let finished = CFAbsoluteTimeGetCurrent()
            let milliseconds = (finished - started) * 1000
            if lastFrameAt > 0 {
                smoothedFps = 0.8 * smoothedFps + 0.2 / max(finished - lastFrameAt, 1e-3)
            }
            lastFrameAt = finished
            let fps = smoothedFps

            var shown: [CountedBox] = []
            var list: [Found] = []
            for (index, detection) in detections.enumerated() {
                let label = OrganismDisplayName.label(detection.label)
                let percent = Int((detection.confidence * 100).rounded())
                // Vision's box is from the bottom left; the preview wants it from the top left.
                shown.append(
                    CountedBox(
                        id: index + 1, label: "\(label) \(percent)%",
                        box: CGRect(
                            x: detection.box.minX, y: 1 - detection.box.maxY,
                            width: detection.box.width, height: detection.box.height)))
                list.append(Found(id: index + 1, label: label, confidence: detection.confidence))
            }
            DispatchQueue.main.async { [weak self] in
                self?.boxes = shown
                self?.found = list
                self?.milliseconds = milliseconds
                self?.framesPerSecond = fps
            }
        }
    }
#endif
