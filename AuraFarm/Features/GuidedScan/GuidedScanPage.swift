import AVFoundation
import AudioToolbox
import SwiftUI

/// The guided scan for a helper: the same engine and the same setup as the slide movement lab
/// (`LabSettings`, `model.start()`, `LabSetupSession`), shown one step at a time in plain
/// words: Align, Focus, Field, Stage, Ready; then the coverage and the scan, then the results
/// screen. Only the presentation is the page's. Debug builds only until the engine moves into
/// the release app.
struct GuidedScanPage: View {
    @Binding var details: SampleDetails
    /// Called with the saved sweep's folder name when the run is saved; the page then closes.
    var onSaved: (String) -> Void = { _ in }
    /// Called when the run could not be saved; the page then closes.
    var onFailed: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var model = ScanEngine()
    @State private var session = GuidedScanSession()
    @State private var coverage = GuidedScanCoverage.everySecondColumn
    @State private var hasStarted = false
    @State private var manualPaused = false
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var isConfirmingLeave = false
    /// "Ending after this column" is on; shown at once, then kept in step with the engine.
    @State private var endsAfterColumn = false
    /// Draws the model's detection boxes over the picture; this scan only, never stored.
    @State private var showsDetections = true
    @State private var haptics = HelperHapticPlayer()
    @Environment(\.scenePhase) private var scenePhase
    // How the slide moves in this test (section A to F of the flow); fresh for every page.
    @State private var stageMode = GuidedScanStageMode.undecided
    @State private var modeChoice: StageModeChoiceView.Option?
    @State private var objective = StageObjective.x40
    @State private var driver: AutoStageDriver?
    @State private var stageConnected = false
    @State private var pathChoice = StagePathMode.presetPath
    /// A calibration failure being told to the person (shown once per failure).
    @State private var failureKind: AutoStageDriver.CalibrationFailureKind?
    @State private var alertedFailures = 0
    /// Autonomous or manual with the Terraloka Stage; Autonomous every time the page opens.
    @State private var controlChoice = StageControlMode.autonomous
    @State private var isConfirmingSwitch = false
    @State private var isConfirmingLook = false
    /// The arrow pad's step size and arrow direction sheet.
    @State private var showsPadSettings = false
    #if DEBUG
        /// The Debug state picker covers the page; it never goes back to a live scan.
        @State private var isPreviewingScanPage = false
        @State private var isConfirmingPreview = false
    #endif
    /// The operator pressed Start Aligning on the first screen after choosing the stage.
    @State private var startedAligning = false
    /// Continue was pressed on the alignment instructions; the live alignment screen follows.
    @State private var alignIntroDone = false
    @AppStorage("slideLab.stageObjective") private var lastObjectiveName = StageObjective.x40.rawValue
    // The lab's own display settings.
    @AppStorage("slideLab.centreField") private var centresField = true
    @AppStorage("slideLab.straighten") private var straightens = true
    /// Records the camera's frames in the background; read when the camera starts, so changing it
    /// here starts or stops the recording from that point.
    @AppStorage("guidedScan.recordLensVideo") private var recordsVideo = true

    var body: some View {
        dressedBody
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { closeButton }
            }
            .confirmationDialog(
                "Leave this look?", isPresented: $isConfirmingLook, titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) { closeStage { dismiss() } }
                Button("Stay", role: .cancel) {}
            } message: {
                Text("Nothing is saved.")
            }
            .confirmationDialog(
                "Switch to autonomous?", isPresented: $isConfirmingSwitch, titleVisibility: .visible
            ) {
                Button("Switch") { driver?.switchToAutonomous(nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    driver?.isCalibrated == true
                        ? "You then choose the path and start."
                        : "The stage goes to its centre, warms up and calibrates. You then choose the path and start."
                )
            }
            .confirmationDialog(
                "Stop this scan?", isPresented: $isConfirmingLeave, titleVisibility: .visible
            ) {
                Button("Stop and discard", role: .destructive) {
                    model.stop()
                    closeStage { dismiss() }
                }
                Button("Keep scanning", role: .cancel) {}
            } message: {
                Text("Nothing is saved unless you use End run.")
            }
            // The lab's settings sequence and syncs, and its start: model.start() on open.
            .modifier(
                LabSettingsSync(
                    model: model,
                    transform: {
                        $0.forGuidedScan(
                            coverage: coverage.rawValue,
                            recordsVideo: recordsVideo && !isManualSession)
                    },
                    onReady: {
                        // Align and focus wait for a Confirm tap, like the field review.
                        model.setConfirmsSetupSteps(true)
                        // Setup waits until a mode is chosen (and the stage is connected).
                        model.setSetupHeld(true)
                        model.setKeepsScreenAwake(true)
                        model.start()
                    })
            )
            .onAppear {
                objective = StageObjective(rawValue: lastObjectiveName) ?? .x40
            }
            .onDisappear {
                model.stop()
                model.setFinishesOnlyOnRequest(false)
                driver?.deactivate()
            }
            .onChange(of: isConfirmingSwitch || isConfirmingLook || isConfirmingLeave || showsPadSettings) {
                _, open in
                if open { driver?.handReleaseAll() }
            }
            .onChange(of: isManualSession) { _, manual in
                // A manual look saves nothing: the recording so far goes, and a later
                // autonomous run records afresh (the settings sync starts it).
                if manual, !hasStarted { model.discardLensVideo() }
            }
            .onChange(of: driver?.calibrationFailureCount) { _, count in
                guard let driver, let count, count > alertedFailures, case .failed = driver.phase
                else { return }
                alertedFailures = count
                failureKind = driver.lastCalibrationFailure
                model.logEvent(
                    "calibration_failed_popup",
                    detail: failureKind == .board ? "board" : "tracking")
            }
            .alert(
                "Calibration didn't work",
                isPresented: Binding(
                    get: { failureKind != nil }, set: { if !$0 { failureKind = nil } }),
                presenting: failureKind
            ) { kind in
                if kind == .tracking {
                    Button("Use preset moves") {
                        logPopup(kind, "use_preset_moves")
                        usePresetMoves()
                    }
                }
                Button("Try again") {
                    logPopup(kind, "try_again")
                    driver?.retryCalibration()
                }
                Button("Cancel", role: .cancel) { logPopup(kind, "cancel") }
            } message: { kind in
                Text(failureMessage(kind))
            }
            .onChange(of: driver?.client.status) { _, status in
                guard status == .connected, !stageConnected else { return }
                stageConnected = true
                model.setSetupHeld(false)
                model.logEvent("stage_connected")
            }
            .onChange(of: scenePhase) { _, phase in
                // The stage stops when the app leaves the screen, during the warm-up and
                // calibration too; it never starts by itself.
                guard phase == .background, let driver else { return }
                driver.cancelSwitchToManual()
                if hasStarted || driver.client.status == .connected { driver.pause() }
            }
    }

    /// The scan with the operator's screens over it. Apart from `body`, whose chain is long
    /// enough for the compiler already.
    private var dressedBody: some View {
        scanBody
            .overlay { operatorScreen.ignoresSafeArea() }
            // The run is done: a moment of loading, then the page saves and the results open.
            .overlay {
                if hasStarted, model.runControl.isFinished {
                    OperatorLoadingScreen().ignoresSafeArea().transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.3), value: model.runControl.isFinished)
            // The pad's sheet; its arrows are let go when it opens (see the onChange above).
            .sheet(isPresented: $showsPadSettings) {
                if let driver { ArrowDirectionSheet(driver: driver, showsStep: true) }
            }
            #if DEBUG
                .overlay(alignment: .topTrailing) {
                    if showsOperatorScreen { debugMenu }
                }
                .overlay(alignment: .bottomLeading) {
                    if hasStarted, !isPreviewingScanPage {
                        ScanDebugButton { isConfirmingPreview = true }
                    }
                }
                .confirmationDialog(
                    "Stop and discard this scan to preview?", isPresented: $isConfirmingPreview,
                    titleVisibility: .visible
                ) {
                    Button("Stop and discard", role: .destructive) { stopForScanPreview() }
                    Button("Cancel", role: .cancel) {}
                }
                .overlay {
                    if isPreviewingScanPage {
                        ScanPagePreview(onClose: { dismiss() })
                    }
                }
            #endif
            .navigationTitle(showsOperatorScreen || hasStarted ? "" : "Guided scan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbarBackground(showsOperatorScreen ? .hidden : .automatic, for: .navigationBar)
            // While scanning the top bar draws its own X, in the same place.
            .toolbar(hasStarted || showsScanPreview ? .hidden : .automatic, for: .navigationBar)
    }

    private var showsScanPreview: Bool {
        #if DEBUG
            isPreviewingScanPage
        #else
            false
        #endif
    }

    #if DEBUG
        /// The Debug picker's way in from the Stage choice screen: nothing runs behind it.
        private func startScanPreview() {
            model.stop()
            driver?.deactivate()
            driver = nil
            stageConnected = false
            isPreviewingScanPage = true
        }

        /// From a live scan: what Stop and discard does to the run and the stage, then the picker.
        private func stopForScanPreview() {
            model.stop()
            closeStage {
                driver = nil
                stageConnected = false
                isPreviewingScanPage = true
            }
        }
    #endif

    #if DEBUG
        /// For testing the screens with no microscope: the operator screens hide the More menu,
        /// so this walks the intro screens and skips the camera checks (alignment and focus
        /// can't pass without a real picture).
        private var debugMenu: some View {
            Menu("Debug", systemImage: "hammer") {
                Button("Next screen", systemImage: "forward") {
                    if !startedAligning {
                        startedAligning = true
                    } else if !alignIntroDone {
                        alignIntroDone = true
                    } else {
                        model.confirmSetupStep()
                    }
                }
                Button("Skip setup", systemImage: "forward.end") {
                    startedAligning = true
                    alignIntroDone = true
                    model.skipSetup()
                }
            }
            .padding(10).background(.thinMaterial, in: Capsule())
            .padding(.trailing, 16).padding(.top, 60)
        }
    #endif

    private var closeButton: some View {
        Button("Close", systemImage: "xmark", action: closeTapped)
    }

    private func closeTapped() {
        if hasStarted {
            isConfirmingLeave = true
        } else if isManualSession {
            isConfirmingLook = true
        } else {
            // Before Start scan too: END clears a warm-up path the stage
            // still holds and sends it home.
            closeStage { dismiss() }
        }
    }

    /// Start, Alignment and Focus use the operator's full-screen designs once the stage is
    /// chosen (and, for the Terraloka Stage, connected). The field and the stage's own
    /// calibration keep the page's views.
    private var showsOperatorScreen: Bool {
        guard !hasStarted, stageMode != .undecided, !isSetupHeld else { return false }
        return !startedAligning || stage == .align || stage == .focus
    }

    @ViewBuilder
    private var operatorScreen: some View {
        if showsOperatorScreen {
            Group {
                if !startedAligning {
                    OperatorStartScreen { startedAligning = true }
                } else if stage == .align, !alignIntroDone {
                    OperatorAlignIntro { alignIntroDone = true }
                } else if stage == .align {
                    OperatorAlignScreen(model: model)
                        // Good alignment moves on by itself after a moment on green.
                        .task(id: model.setupInfo.isAlignmentPassed) {
                            guard model.setupInfo.isAlignmentPassed else { return }
                            try? await Task.sleep(for: .seconds(1))
                            // Lost again before the moment was up: nothing to confirm.
                            guard !Task.isCancelled else { return }
                            model.confirmSetupStep()
                        }
                } else {
                    OperatorFocusScreen(model: model)
                        // The person can always say it is sharp; hidden once the checks agree.
                        .overlay(alignment: .bottom) {
                            VStack(spacing: 8) {
                                newSpotButton
                                acceptFocusButton
                            }
                            .padding(.horizontal).padding(.bottom, 40)
                        }
                        .task(id: model.setupInfo.focus?.state == .focused) {
                            guard model.setupInfo.focus?.state == .focused else { return }
                            try? await Task.sleep(for: .seconds(1.5))
                            // Lost again before the moment was up: nothing to confirm.
                            guard !Task.isCancelled else { return }
                            model.confirmSetupStep()
                        }
                }
            }
            .transition(.opacity)
        }
    }

    /// The lab's own step, named for a helper.
    private var stage: GuidedScanSetupStage { .current(step: model.setupInfo.step) }

    /// Top to bottom, nothing overlapping: the top bar, the picture (it shrinks first), the speed
    /// bar, and the instruction card in space of its own that nothing is drawn over.
    private var scanBody: some View {
        Group {
            if stageMode == .undecided {
                choicePage
            } else {
                ScanLayoutView(pinsToTop: hasStarted && isTerraloka) {
                    // Above the picture for touches too, whatever the picture does. The operator
                    // screens draw their own chrome over the picture.
                    if !showsOperatorScreen { topLine.zIndex(1) }
                } picture: {
                    picture
                } bottom: {
                    if !showsOperatorScreen { bottom }
                }
            }
        }
        // The Manual pad's press handling, flips, 100x note and release are the hand pad's own,
        // on for as long as the pad is on screen.
        .background {
            if let driver, hasStarted, isTerraloka, scanState.card == .manualPad {
                Color.clear.handPadSupport(driver)
            }
        }
        // The Field Helper's warm glow while scanning, kept dark like the rest of the page.
        .background {
            if hasStarted {
                Color.clear.auraBackground().environment(\.colorScheme, .dark)
                    .ignoresSafeArea()
            }
        }
        .background(.black)
        .foregroundStyle(.white)
        .background(
            GuidedScanHaptics(
                model: model, session: session, player: haptics, plays: !isTerraloka)
        )
        .onChange(of: showsDetections) { _, shown in model.setShowsDetections(shown) }
        .onChange(of: model.runControl.pendingEnd) { _, pending in endsAfterColumn = pending }
        .onChange(of: model.runSummary) { _, record in
            guard let record else { return }
            save(record)
        }
    }

    /// "How will the slide move?": a page of its own, without the camera picture.
    private var choicePage: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let problem = cameraProblem {
                    Text(problem).font(.subheadline).foregroundStyle(.red)
                }
                StageModeChoiceView(
                    selection: $modeChoice, objective: $objective, control: $controlChoice,
                    onContinue: continueFromChoice)
                #if DEBUG
                    Button("Preview Scan page", systemImage: "hammer", action: startScanPreview)
                        .buttonStyle(.bordered).tint(.white)
                #endif
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The mechanical stage keeps its ladybug in the top bar; the Terraloka stage's is under the
    /// lens.
    private var mechanicalLadybug: (showsBoxes: Bool, action: () -> Void)? {
        isTerraloka ? nil : (showsBoxes: scanState.showsBoxes, action: { showsDetections.toggle() })
    }

    /// Setup: "Step 2 of 4: Find the eyepiece" and More. The scan: the X, the farm and plot, End
    /// and Pause (`ScanTopBar`).
    @ViewBuilder
    private var topLine: some View {
        if hasStarted {
            ScanTopBar(
                top: scanState.top, actions: scanActions,
                ladybug: mechanicalLadybug)
        } else {
            HStack {
                Spacer()
                if !isSetupHeld {
                    Menu("More", systemImage: "ellipsis.circle") {
                        Button("Skip setup", systemImage: "forward.end") { model.skipSetup() }
                        Button("Redo setup", systemImage: "arrow.counterclockwise") {
                            model.redoSetup()
                        }
                    }
                    .font(.headline)
                }
            }
            .font(.headline.monospacedDigit())
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    /// The lab's own picture container: preview gravity, display transform and centring.
    private var picture: some View {
        GeometryReader { proxy in
            let isCentred = stage.treatment.centres && centresField && model.isAnalyzing
            let display =
                isCentred
                ? FramePreviewConverter.displayTransform(
                    for: model.fieldInfo, layer: previewLayer, viewSize: proxy.size,
                    stage: straightens ? (model.setupInfo.stageAxes ?? .identity) : .identity)
                : .identity
            let converter = FramePreviewConverter(
                layer: previewLayer, frameSize: model.fieldInfo.frameSize, display: display)
            let zooms = hasStarted || (showsOperatorScreen && stage == .focus)
            let round = zooms ? learnedRect(model.fieldInfo, converter) : nil
            // Scanning and focusing show the round view big enough to see clearly, with room round it.
            let zoom = round.map { min(max(proxy.size.width * 0.8 / $0.width, 0.5), 2.5) }
            ZStack {
                CameraPreview(
                    session: model.session,
                    onLayer: {
                        $0.videoGravity = .resizeAspect
                        previewLayer = $0
                    }
                )
                // The picture is only looked at: a centred picture is drawn larger than its frame,
                // and its view must not catch taps meant for the top bar above it.
                .allowsHitTesting(false)
                .transformEffect(display)
                // Scanning shows only the circle the field step found; the screen's background
                // shows round it.
                .mask {
                    if let round {
                        ZStack {
                            Circle().frame(width: round.width, height: round.height)
                                .position(x: round.midX, y: round.midY)
                        }
                    } else {
                        Rectangle()
                    }
                }
                if model.isAnalyzing {
                    overlays(display: display, isCentred: isCentred)
                } else {
                    ProgressView("Starting the camera…").tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .scaleEffect(zooms ? zoom ?? 1 : 1, anchor: zooms ? round.map {
                UnitPoint(x: $0.midX / proxy.size.width, y: $0.midY / proxy.size.height)
            } ?? .center : .center)
            .offset(x: zooms ? round.map { proxy.size.width / 2 - $0.midX } ?? 0 : 0,
                    y: zooms ? round.map { proxy.size.height / 2 - $0.midY } ?? 0 : 0)
            // Clip after the zoom, so the ring round the view is not cut off.
            .clipShape(Rectangle())
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        // A nil ratio makes a GeometryReader square, so the full screen asks for the screen's ratio.
        .aspectRatio(
            isFullScreenCamera ? UIScreen.main.bounds.width / UIScreen.main.bounds.height : 1,
            contentMode: .fit)
        .ignoresSafeArea(isFullScreenCamera ? .all : [])
        .clipped()
        // The same preview layer, filled instead of fitted: no second camera view is made.
        .onChange(of: isFullScreenCamera) { _, full in
            previewLayer?.videoGravity = full ? .resizeAspectFill : .resizeAspect
        }
    }

    /// The live alignment screen: the page's camera picture fills the screen.
    private var isFullScreenCamera: Bool {
        showsOperatorScreen && startedAligning && alignIntroDone && (stage == .align || stage == .focus)
    }

    /// What is drawn on the picture at each step: only what the lab draws there. Align draws
    /// nothing (its checks are the ticks below); focus, the field review and the stage step
    /// are the lab's own views.
    @ViewBuilder
    private func overlays(display: CGAffineTransform, isCentred: Bool) -> some View {
        let info = model.fieldInfo
        let converter = FramePreviewConverter(
            layer: previewLayer, frameSize: info.frameSize, display: display)
        ZStack {
            switch stage {
            case .align:
                if model.setupInfo.isAlignmentPassed, !isSetupHeld, !showsOperatorScreen {
                    confirmPanel(
                        question: "Is the phone aligned?",
                        detail: "The whole round view is in the picture, round and evenly lit.")
                }
            case .focus:
                darkOutside(info, converter, isCentred)
                if !showsOperatorScreen {
                    LiveSetupOverlay(
                        model: model, previewLayer: previewLayer, showsIndicator: false,
                        display: display)
                }
                if model.setupInfo.focus?.state == .focused, !showsOperatorScreen {
                    confirmPanel(
                        question: "Is the picture sharp?",
                        detail: "Best focus found. Keep the knob still and confirm.")
                }
            case .field:
                LiveFieldOutlines(
                    model: model, previewLayer: previewLayer, display: display,
                    darkensOutside: true)
                LiveFieldCard(model: model)
                if info.awaitingReview {
                    FieldReview(
                        info: info,
                        converter: FramePreviewConverter(
                            layer: previewLayer, frameSize: info.frameSize),
                        onConfirm: { model.confirmField() },
                        onAdjust: { model.adjustField(to: $0) })
                }
            case .stage:
                darkOutside(info, converter, isCentred)
                GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                LiveSetupOverlay(
                    model: model, previewLayer: previewLayer, showsIndicator: false,
                    automatedStage: isTerraloka, display: display)
            case .ready:
                if !hasStarted { darkOutside(info, converter, isCentred) }
                GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                // The eye button, or the organisms seen while steering by hand (not counted).
                if ScanBoxes.shown(
                    showsDetections: showsDetections, hasStarted: hasStarted,
                    handHoldOn: model.handHold == .on)
                {
                    LiveDetectionBoxes(model: model, converter: converter)
                }
                if hasStarted {
                    // The ring and its arrow (below) are the guide here, not the lab's cross and
                    // rings. The edge line shows only while the card asks about it; the eye is
                    // for the organisms alone.
                    if !isTerraloka, session.display?.questionID != nil {
                        EdgeLineOverlay(state: model.edgeLineState, mapper: converter)
                    }
                    PausedOverlay(
                        monitor: model.setupInfo.monitor, mapper: converter,
                        onResumeAnyway: nil, showsControls: !isTerraloka)
                    OperatorScanRing(
                        circle: learnedRect(info, converter), phase: scanPhase, showsArrow: !isTerraloka,
                        fraction: stageProgress?.fraction
                            ?? columnProgress.map { Double($0.done) / Double($0.total) } ?? 0,
                        direction: model.overlayState.model?.arrowDirection,
                        isEmpty: isTerraloka && scanState.ringIsEmpty)
                }
            }
        }
    }

    /// The learned round view as a rectangle in the picture's space, nil until it is found.
    private func learnedRect(
        _ info: SlideMovementInfo.Field, _ converter: FramePreviewConverter?
    ) -> CGRect? {
        // The engine clears the field while setup runs, so the focus step brings its own circle.
        guard let converter,
            let c = info.state?.mask.flatMap({ FieldCircle(fitting: $0) })
                ?? model.setupInfo.focusCircle
        else { return nil }
        let box = converter.layerRect(
            of: CGRect(
                x: c.centre.x - c.radius, y: c.centre.y - c.radius,
                width: c.radius * 2, height: c.radius * 2))
        // A circle, never an oval: a sheared picture makes the bounding box uneven.
        let r = Path(ellipseIn: box).applying(converter.display).boundingRect
        let side = min(r.width, r.height)
        return CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
    }

    /// The align and focus confirmation, over the top of the picture like the field review's.
    private func confirmPanel(question: String, detail: String) -> some View {
        VStack {
            SetupConfirmPanel(
                question: question, detail: detail, buttonTitle: "Looks right"
            ) { model.confirmSetupStep() }
            Spacer()
        }
    }

    /// Only the dark outside of the round view, without the lab's yellow box.
    @ViewBuilder
    private func darkOutside(
        _ info: SlideMovementInfo.Field, _ converter: FramePreviewConverter?, _ isCentred: Bool
    ) -> some View {
        if isCentred, stage.treatment.darkensOutside {
            FieldOutlines(
                info: Self.withoutBox(info), converter: converter, darkensOutside: true)
        }
    }

    private static func withoutBox(_ info: SlideMovementInfo.Field) -> SlideMovementInfo.Field {
        var copy = info
        copy.registrationRect = nil
        return copy
    }

    @ViewBuilder
    private var bottom: some View {
        if hasStarted {
            if isTerraloka {
                ScanBottomView(state: scanState, actions: scanActions)
            } else {
                scanBottom
            }
        } else {
            setupBottom
        }
    }

    /// The step's instruction in the card's own space, and under it what the step needs: the
    /// way to move the slide first, then the coverage and Start scan once setup is done.
    private var setupBottom: some View {
        VStack(spacing: 10) {
            if let problem = cameraProblem {
                Text(problem).font(.subheadline).foregroundStyle(.red)
            }
            switch stageMode {
            case .undecided:
                EmptyView()  // a page of its own: `choicePage`
            case .terraloka where !stageConnected:
                StageConnectingCard(
                    client: driver?.client.status ?? .idle,
                    onRetry: { driver?.client.connect() }, onBack: backToChoice)
            case .terraloka:
                terralokaSetupCards
            case .manual:
                manualSetupCards
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var manualSetupCards: some View {
        VStack(spacing: 10) {
            SetupCardView(
                sentence: stage.sentence,
                notice: stage == .align && model.setupInfo.resumeStep != nil
                    ? AlignOverlay.lostText : nil,
                ticks: stage == .align
                    ? AlignmentTicks(
                        reading: model.setupInfo.alignment,
                        passed: model.setupInfo.isAlignmentPassed) : nil)
            acceptFocusButton
            if stage == .ready {
                CoverageChoiceView(coverage: $coverage)
                recordVideoToggle
                bigButton("Start scan", action: startScan)
            }
        }
    }

    /// The person can always say it is sharp: the checks cannot judge every sample. Hidden once
    /// the checks agree and ask by themselves.
    @ViewBuilder
    private var acceptFocusButton: some View {
        if stage == .focus, model.setupInfo.focus?.state != .focused {
            bigButton("It's sharp, continue", isProminent: false) { model.acceptFocus() }
        }
    }

    /// The mechanical stage cannot tell the app it moved: the operator says the view is somewhere
    /// new, and the focus check starts afresh. (The Terraloka stage says it itself.)
    @ViewBuilder
    private var newSpotButton: some View {
        if stage == .focus, !isTerraloka {
            bigButton("I'm at a new spot", isProminent: false) { model.focusSpotChanged() }
        }
    }

    private var recordVideoToggle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Record video of the sample", isOn: $recordsVideo)
            Text("Uses about 60 MB a minute.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
    }

    private func calibrationCard(_ driver: AutoStageDriver) -> some View {
        StageCalibrationCard(
            status: driver.status, isPaused: driver.phase == .paused,
            onRetry: { driver.retryCalibration() }, onResume: { driver.resume() },
            onFocused: { driver.focusIsSharp() },
            onBackToManual: driver.canBackToManual ? { driver.backToManual() } : nil,
            onUsePreset: driver.lastCalibrationFailure == .tracking
                ? { usePresetMoves() } : nil)
    }

    private func logPopup(_ kind: AutoStageDriver.CalibrationFailureKind, _ button: String) {
        model.logEvent(
            "calibration_failed_popup",
            detail: "\(kind == .board ? "board" : "tracking"): \(button)")
    }

    private func failureMessage(_ kind: AutoStageDriver.CalibrationFailureKind) -> String {
        switch kind {
        case .tracking:
            "There is too little sample in view for the camera to track the movement reliably. Preset moves don't need calibration, so you can use them instead."
        case .board:
            if case .failed(let reason)? = driver?.phase { reason } else { "The stage did not answer." }
        }
    }

    /// Calibration did not work: preset moves instead. The board is made ready; nothing moves.
    private func usePresetMoves() {
        pathChoice = .presetPath
        driver?.choosePath(.presetPath)
    }

    /// The path card follows what is chosen: preset moves prepare the board at once; Follow the
    /// guide waits for its button, unless it is measured already.
    private func syncPathChoice(_ driver: AutoStageDriver) {
        guard driver.canChoosePath else { return }
        switch pathChoice {
        case .presetPath:
            if driver.pathMode != .presetPath || driver.phase == .choosingPath {
                driver.choosePath(.presetPath)
            }
        case .followGuide:
            if driver.isCalibrated, driver.pathMode != .followGuide || driver.phase == .choosingPath {
                driver.choosePath(.followGuide)
            }
        }
    }

    /// Step 4 in an autonomous test: the path first; calibration only if Follow the guide asks.
    @ViewBuilder
    private func pathCards(_ driver: AutoStageDriver) -> some View {
        switch driver.phase {
        case .choosingPath, .readyToStart, .calibrated, .preparingManual, .waitingForStageStep:
            pathCard(driver)
        case .paused where driver.manualProblem != nil:
            pathCard(driver)
        default:
            calibrationCard(driver)
        }
    }

    private func pathCard(_ driver: AutoStageDriver) -> some View {
        let isConnected = driver.client.status == .connected
        return VStack(spacing: 10) {
            StagePathChoiceView(pathMode: $pathChoice, coverage: $coverage, objective: objective)
            if driver.phase == .preparingManual {
                Text("Getting the stage ready…").font(.subheadline).foregroundStyle(.secondary)
            }
            switch driver.manualProblem {
            case .oldPath?:
                Text("The stage still holds an old path. Go to centre clears it.")
                    .font(.subheadline)
                bigButton("Go to centre") { driver.goToCentre() }
            case .noAnswer?:
                Text("The stage did not answer").font(.subheadline)
                bigButton("Retry") { driver.resume() }
            case nil:
                EmptyView()
            }
            recordVideoToggle
            if pathChoice == .followGuide, !driver.isCalibrated {
                bigButton(
                    "Calibrate and continue",
                    isEnabled: isConnected && driver.phase != .preparingManual
                ) { driver.choosePath(.followGuide) }
            } else {
                bigButton(
                    "Start scan", isEnabled: isConnected && driver.phase == .readyToStart,
                    action: startScan)
            }
            if !isConnected {
                Text("Waiting for the stage to reconnect…")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if driver.canBackToManual {
                bigButton("Back to manual", isProminent: false) { driver.backToManual() }
            }
        }
        .onChange(of: pathChoice) { syncPathChoice(driver) }
        .onChange(of: driver.phase, initial: true) { syncPathChoice(driver) }
    }

    /// A manual session: look only. The pad, and the ways to carry on or switch.
    @ViewBuilder
    private func manualCards(_ driver: AutoStageDriver) -> some View {
        switch driver.phase {
        case .byHand:
            StageHandPad(driver: driver, isCompact: true)
            manualFooter(driver)
        case .paused:
            VStack(alignment: .leading, spacing: 10) {
                if let notice = driver.restartNotice {
                    Text(notice).font(.subheadline)
                }
                switch driver.manualProblem {
                case .oldPath?:
                    Text("The stage still holds an old path. Go to centre clears it.")
                        .font(.subheadline)
                    bigButton("Go to centre") { driver.goToCentre() }
                case .noAnswer?:
                    Text("The stage did not answer").font(.subheadline)
                    bigButton("Retry") { driver.continueManually() }
                case nil:
                    bigButton("Continue") { driver.continueManually() }
                }
                bigButton("Switch to autonomous", isProminent: false) { isConfirmingSwitch = true }
                    .disabled(!driver.canSwitchToAutonomous)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 20))
        case .disconnected:
            StageRunStatusCard(
                status: driver.status, isPaused: false,
                actions: alertActions(.disconnected, driver), onPause: {}, onResume: {})
        default:
            StageCalibrationCard(
                status: AutoStageStatus(title: "Getting the stage ready…"), onRetry: {})
        }
    }

    private func manualFooter(_ driver: AutoStageDriver) -> some View {
        VStack(spacing: 8) {
            Text("Look only. Nothing is saved.").font(.subheadline).foregroundStyle(.secondary)
            bigButton("Switch to autonomous", isProminent: false, isEnabled: driver.canSwitchToAutonomous) {
                isConfirmingSwitch = true
            }
        }
    }

    @ViewBuilder
    private var terralokaSetupCards: some View {
        if let driver {
            let status = driver.status
            if driver.controlMode == .manual, stage == .stage || stage == .ready {
                manualCards(driver)
            } else {
            switch stage {
            case .stage, .ready:
                pathCards(driver)
            default:
                if status.needsPerson == .disconnected {
                    StageRunStatusCard(
                        status: status, isPaused: false,
                        actions: alertActions(.disconnected, driver), onPause: {}, onResume: {})
                }
                SetupCardView(
                    sentence: stage.sentence,
                    notice: stage == .align && model.setupInfo.resumeStep != nil
                        ? AlignOverlay.lostText : nil,
                    ticks: stage == .align
                        ? AlignmentTicks(
                            reading: model.setupInfo.alignment,
                            passed: model.setupInfo.isAlignmentPassed) : nil)
                acceptFocusButton
            }
            }
        }
    }

    // MARK: The Terraloka Stage

    private var isTerraloka: Bool {
        if case .terraloka = stageMode { return true }
        return false
    }

    /// Step 4 of an autonomous test before any calibration really runs.
    private var isChoosingPath: Bool {
        guard let driver, driver.controlMode == .autonomous, stage == .stage || stage == .ready
        else { return false }
        switch driver.phase {
        case .warmingUp, .calibrating, .failed, .waitingForFocus: return false
        default: return true
        }
    }

    /// A look with the Terraloka Stage's arrows: nothing is counted and nothing is saved.
    private var isManualSession: Bool { isTerraloka && driver?.controlMode == .manual }

    /// The stage is steered by hand, coming back, or a saved position waits.
    private var isAwayFromPath: Bool {
        guard let driver else { return false }
        switch driver.phase {
        case .byHand, .returningFromHand, .checkingFocus: return true
        default: return driver.handSaved != nil
        }
    }

    /// The preset moves: the stage's own columns, not the guide's.
    private var isFixedSweep: Bool { isTerraloka && driver?.pathMode == .presetPath }

    /// No setup step advances until a mode is chosen and, for the stage, it is connected.
    private var isSetupHeld: Bool {
        switch stageMode {
        case .undecided: true
        case .manual: false
        case .terraloka: !stageConnected
        }
    }

    private var setupTitle: String {
        switch stageMode {
        case .undecided: "Start"
        case .terraloka where !stageConnected: "Connecting"
        case .terraloka where isManualSession && (stage == .stage || stage == .ready): "Manual"
        case .terraloka where isChoosingPath: "Step 4 of \(GuidedScanSetupStage.stepCount): Choose the path"
        default: stage.indicator(automatedStage: isTerraloka)
        }
    }

    private var columnText: String {
        if isFixedSweep, case .presetPath(let column, _)? = driver?.phase, column > 0 {
            return "Column \(column)"
        }
        return isFixedSweep ? "" : (session.display?.columnText ?? "")
    }

    /// Continue on the first screen.
    private func continueFromChoice() {
        switch modeChoice {
        case .manual:
            stageMode = .manual
            model.setSetupHeld(false)
            model.logEvent("stage_choice", detail: "manual")
        case .terraloka:
            lastObjectiveName = objective.rawValue
            coverage = GuidedScanCoverage.recommended(for: objective)
            let stageDriver = AutoStageDriver(engine: model)
            stageDriver.controlMode = controlChoice
            stageDriver.objective = objective
            stageDriver.chunkDegrees = objective.defaultChunk
            stageDriver.requiresRunStart = true
            stageDriver.autoEndsOnGuideFinish = true
            stageDriver.asksEdgeQuestions = false  // the stage decides at the edges
            stageDriver.guideIsStraightened = straightens && centresField
            // One quiet tick when something needs the person; it follows the ringer switch.
            stageDriver.alertSink = { _ in AudioServicesPlaySystemSound(1104) }
            stageDriver.activate(restoringAsksEdges: false)
            driver = stageDriver
            stageConnected = false
            stageMode = .terraloka(objective)
            model.logEvent(
                "stage_choice", detail: controlChoice == .manual ? "terraloka_manual" : "terraloka")
        case nil: break
        }
    }

    /// Back from the connecting card to the first screen.
    private func backToChoice() {
        driver?.deactivate()
        driver = nil
        stageConnected = false
        stageMode = .undecided
    }

    /// Ends the stage's session (END: home) and lets go of it; `then` runs a moment later so END
    /// has left the phone.
    private func closeStage(then finish: @escaping () -> Void) {
        guard let driver else { return finish() }
        driver.endSession()
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            driver.deactivate()
            finish()
        }
    }

    /// The buttons an alert needs.
    private func alertActions(_ alert: AutoStageAlert, _ driver: AutoStageDriver)
        -> [(title: String, run: () -> Void)]
    {
        switch alert {
        case .focusPause:
            var actions: [(title: String, run: () -> Void)] = [
                ("Resume anyway", { model.resumeFocusAnyway() })
            ]
            if driver.canConfirmEmptyArea {
                actions.append(("In focus – empty area", { driver.confirmEmptyArea() }))
            }
            return actions
        case .stageRestarted: return [("Resume", { driver.resume() })]
        case .disconnected: return [("Retry", { driver.client.connect() })]
        case .emptyCapReached:
            return [
                ("Keep crossing", { driver.keepCrossing() }),
                ("End column here", { driver.endColumnHere() }),
            ]
        case .calibrationFailed: return []
        case .focusFirst: return [("It's sharp. Calibrate", { driver.focusIsSharp() })]
        }
    }

    private func bigButton(
        _ title: String, isProminent: Bool = true, isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .tint(isProminent ? nil : .gray)
        .disabled(!isEnabled)
    }

    /// An End run choice: shown at once, then handed to the engine.
    private func chooseEnd(_ item: EndRunMenu.Item) {
        switch item {
        case .endAfterColumn: endsAfterColumn = true
        case .undo: endsAfterColumn = false
        case .discard: isConfirmingLeave = true  // the same question as the X; nothing is lost before it
        case .endNow, .keepScanning: break
        }
        if let action = item.action {
            if action != .cancel { driver?.cancelSwitchToManual() }
            model.endRun(action)
        }
    }

    /// Begins the scan: logging is on for every guided scan (the movement CSV and the run
    /// record), then Mark start, as the lab's buttons do.
    private func startScan() {
        if driver?.controlMode == .manual { return }  // a look never becomes a run
        details.recordedAt = .now
        if let driver, case .terraloka = stageMode {
            driver.setPathMode(pathChoice)
            // The preset moves covers the stage's own range: the run ends when the stage's path
            // does, not when the guide's plan does.
            model.setFinishesOnlyOnRequest(pathChoice == .presetPath)
            session.reportsWords = false
            model.setRunStage(
                stage: "terraloka", objective: objective.title,
                pathMode: pathChoice == .followGuide ? "followGuide" : "presetPath")
        } else {
            model.setFinishesOnlyOnRequest(false)
            model.setRunStage(stage: "manual", objective: nil, pathMode: nil)
        }
        session.start(coverage: coverage, rule: GuidedScanSettings.knobRule)
        hasStarted = true
        model.startLog()
        model.markStart()
        if let driver, case .terraloka = stageMode {
            model.logEvent("path_choice_\(pathChoice.rawValue)")
            driver.beginRun()
            Task {
                // Rows apart, so the events do not overwrite each other.
                try? await Task.sleep(for: .milliseconds(300))
                model.logEvent("coverage_\(coverage.rawValue)")
            }
        }
    }

    private var scanPhase: OperatorScanPhase {
        if model.runControl.isFinished { return .complete }
        // The person cannot slow the Terraloka Stage down: its own status shows instead.
        return !isTerraloka && model.speedState.status == .tooFast ? .slowDown : .moving
    }

    /// Finished columns of all columns, for the blocks: from the stage's own progress on the
    /// fixed sweep, otherwise from "Column 3 of 9".
    private var columnProgress: (done: Int, total: Int)? {
        let numbers = columnText.split { !$0.isNumber }.compactMap { Int($0) }
        var counts: (column: Int, total: Int)?
        if isFixedSweep, let p = driver?.presetProgress, p.totalColumns > 0 {
            counts = (p.column, p.totalColumns)
        } else if numbers.count == 2, numbers[1] > 0 {
            counts = (numbers[0], numbers[1])
        }
        guard let counts else { return nil }
        let done = model.runControl.isFinished ? counts.total : max(counts.column - 1, 0)
        return (min(done, counts.total), counts.total)
    }

    private var isPaused: Bool {
        isTerraloka ? driver?.phase == .paused : manualPaused
    }

    /// Paused with a saved position: the stage goes back there before it carries on.
    private var goesBackFirst: Bool {
        guard let driver, isTerraloka else { return false }
        return driver.handSaved != nil && driver.canGoBack
    }

    /// The preset moves' progress; nil in every other run.
    private var stageProgress: StageZigzagProgress? {
        guard isFixedSweep, let driver else { return nil }
        return driver.presetProgress ?? StageZigzagProgress()
    }

    private func togglePause() {
        if let driver, isTerraloka {
            if isPaused {
                goesBackFirst ? driver.goBackAndResume() : driver.resume()
            } else {
                driver.pause()
            }
        } else {
            // shortcut: the engine has no plain pause for the manual stage, so this uses its
            // focus pause (the guide waits); upgrade when the engine gets a real one.
            manualPaused ? model.resumeFocusAnyway() : model.requestFocusPause()
            manualPaused.toggle()
        }
    }

    /// The mechanical stage's words under the picture, or the card when the edge question needs
    /// the person. Pause and End are in the top bar.
    private var scanBottom: some View {
        VStack(spacing: 18) {
            if session.display?.questionID != nil {
                manualScanCard
            } else {
                Text(scanMessage).font(.callout).multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: The Scan page's value and actions

    /// The plain value the scan part of the page is drawn from.
    private var scanState: ScanPageState { .make(scanInput) }

    private var scanInput: ScanPageInput {
        var i = ScanPageInput()
        i.sampleID = details.sampleID
        i.plotName = details.plotName
        i.isOwnSample = details.isOwnSample
        i.date = details.recordedAt
        i.isFinished = model.runControl.isFinished
        i.endingAfterColumn = endsAfterColumn
        i.columnInProgress = model.runControl.columnInProgress && !isFixedSweep
        i.isAwayFromPath = isAwayFromPath
        i.isPaused = isPaused
        i.goesBackFirst = goesBackFirst
        i.fraction =
            stageProgress?.fraction ?? columnProgress.map { Double($0.done) / Double($0.total) } ?? 0
        i.showsBoxes = ScanBoxes.shown(
            showsDetections: showsDetections, hasStarted: hasStarted,
            handHoldOn: model.handHold == .on)
        guard let driver, isTerraloka else { return i }
        i.found = ScanFound.rows(
            Dictionary(model.countInfo.labels.map { ($0.label, $0.map) }, uniquingKeysWith: +))
        i.canChangeMode = driver.phase == .byHand ? driver.canGoBack : driver.canSwitchToManual
        i.pad = ScanPad(
            x: driver.stageAngles.x, y: driver.stageAngles.y, up: driver.handEnabled(.up),
            down: driver.handEnabled(.down), left: driver.handEnabled(.left),
            right: driver.handEnabled(.right), canFineStep: driver.canFineStep)
        i.stage = stageInput(driver)
        return i
    }

    private func stageInput(_ driver: AutoStageDriver) -> ScanStageInput {
        let status = driver.status
        let monitor = model.setupInfo.monitor
        var s = ScanStageInput()
        s.phase = driver.phase
        s.alert = status.needsPerson
        s.isTooHot = status.needsPerson == nil && status.title == HelperInstruction.tooHot.text
        s.connectionText = AutoStageStatus.connectionText(driver.client.status)
        s.isSwitchingToManual = driver.isSwitchingToManual
        s.manualSwitchProblem = driver.manualSwitchProblem
        s.handNote = driver.handNote
        s.handFocusReminder = driver.handFocusReminder
        s.focusHint = monitor.focusHint
        s.dial = monitor.dial
        s.alignmentPaused = monitor.state == .pausedAlignment
        s.isComplete = model.runControl.isFinished
        s.canConfirmEmptyArea = driver.canConfirmEmptyArea
        s.alertButtons = status.needsPerson.map { alertActions($0, driver).map { $0.title } } ?? []
        s.column = columnText.split { !$0.isNumber }.compactMap { Int($0) }.first
        s.fallback = status
        return s
    }

    /// Each action is the call the page made before the redesign.
    private var scanActions: ScanPageActions {
        var a = ScanPageActions()
        a.close = closeTapped
        a.togglePause = togglePause
        a.chooseEnd = chooseEnd
        a.toggleBoxes = { showsDetections.toggle() }
        a.setMode = { mode in
            guard let driver else { return }
            if mode == .manual {
                driver.switchToManual()
            } else if driver.phase == .byHand {
                driver.goBackAndResume()
            }
        }
        a.dismissReminder = { driver?.dismissHandFocusReminder() }
        a.alertAction = { title in
            guard let driver, let alert = driver.status.needsPerson else { return }
            alertActions(alert, driver).first { $0.title == title }?.run()
        }
        a.press = { driver?.handPress($0) }
        a.release = { driver?.handRelease($0) }
        a.openPadSettings = {
            driver?.handReleaseAll()
            showsPadSettings = true
        }
        return a
    }

    private var scanMessage: String {
        switch scanPhase {
        case .complete: "Detection complete"
        case .slowDown: "Slow down"
        case .moving:
            session.display?.card?.text ?? "Keep moving the microscope slide to the forward"
        }
    }

    private var manualScanCard: some View {
        VStack(spacing: 8) {
            HelperCardView(
                card: session.display?.card ?? .waiting("Getting ready…"),
                onYes: { haptics.play(session.answer(.yes, on: model)) },
                onNo: { haptics.play(session.answer(.no, on: model)) })
        }
    }

    // MARK: Words and saving

    private var cameraProblem: String? {
        if let problem = model.cameraError { return problem }
        return model.authorization == .denied ? "Camera access is off. Turn it on in Settings." : nil
    }

    /// Saves the finished run as a sweep; the page closes and the caller shows the results.
    private func save(_ record: GuideRunRecord) {
        let csv = model.summaryItems.first { $0.pathExtension == "csv" }
        do {
            let video = model.summaryItems.first { $0.pathExtension == "mov" }
            let name = try GuidedScanSaver.save(
                details: details, record: record, movementCSV: csv, lensVideo: video,
                organisms: model.summaryOrganisms)
            model.stop()
            closeStage {
                onSaved(name)
                dismiss()
            }
        } catch {
            model.stop()
            closeStage {
                onFailed()
                dismiss()
            }
        }
    }
}

/// "Every 2nd column" or "Every column", asked once setup is done.
struct CoverageChoiceView: View {
    @Binding var coverage: GuidedScanCoverage

    var body: some View {
        VStack(spacing: 10) {
            ForEach(GuidedScanCoverage.allCases) { option in
                Button {
                    coverage = option
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.title).font(.headline)
                            Text(option.detail).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: coverage == option ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(12)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Plays the card's haptic as the engine's state changes, and ticks for a spot.
private struct GuidedScanHaptics: View {
    var model: ScanEngine
    var session: GuidedScanSession
    var player: HelperHapticPlayer
    /// False with the Terraloka Stage: the session still follows the guide (the column text), but
    /// nothing is felt.
    var plays = true

    var body: some View {
        // The overlay changes about ten times a second; each change is one reading.
        Color.clear
            .onChange(of: model.overlayState.model) {
                let haptic = session.refresh(from: model)
                if plays { player.play(haptic) }
            }
    }
}

#Preview("Coverage choice") {
    @Previewable @State var coverage = GuidedScanCoverage.everySecondColumn
    CoverageChoiceView(coverage: $coverage).padding().background(.black).foregroundStyle(.white)
}
