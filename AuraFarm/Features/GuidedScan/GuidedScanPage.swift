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
    @State private var previewLayer: AVCaptureVideoPreviewLayer?
    @State private var isConfirmingLeave = false
    /// "Ending after this column" is on; shown at once, then kept in step with the engine.
    @State private var endsAfterColumn = false
    /// Draws the model's detection boxes over the picture; this scan only, never stored.
    @State private var showsDetections = false
    @State private var haptics = HelperHapticPlayer()
    @Environment(\.scenePhase) private var scenePhase
    // How the slide moves in this test (section A to F of the flow); fresh for every page.
    @State private var stageMode = GuidedScanStageMode.undecided
    @State private var modeChoice: StageModeChoiceView.Option?
    @State private var objective = StageObjective.x40
    @State private var driver: AutoStageDriver?
    @State private var stageConnected = false
    @State private var pathChoice = StagePathMode.followGuide
    /// Autonomous or manual with the Terraloka Stage; Autonomous every time the page opens.
    @State private var controlChoice = StageControlMode.autonomous
    @State private var isConfirmingSwitch = false
    @State private var isConfirmingLook = false
    @AppStorage("slideLab.stageObjective") private var lastObjectiveName = StageObjective.x40.rawValue
    // The lab's own display settings.
    @AppStorage("slideLab.centreField") private var centresField = true
    @AppStorage("slideLab.straighten") private var straightens = true
    /// Records the camera's frames in the background; read when the camera starts, so changing it
    /// here starts or stops the recording from that point.
    @AppStorage("guidedScan.recordLensVideo") private var recordsVideo = true

    var body: some View {
        scanBody
            .navigationTitle("Guided scan")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") {
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
                }
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
            .onChange(of: isConfirmingSwitch || isConfirmingLook || isConfirmingLeave) { _, open in
                if open { driver?.handReleaseAll() }
            }
            .onChange(of: isManualSession) { _, manual in
                // A manual look saves nothing: the recording so far goes, and a later
                // autonomous run records afresh (the settings sync starts it).
                if manual, !hasStarted { model.discardLensVideo() }
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
                if hasStarted || driver.client.status == .connected { driver.pause() }
            }
    }

    /// The lab's own step, named for a helper.
    private var stage: GuidedScanSetupStage { .current(step: model.setupInfo.step) }

    /// Top to bottom, nothing overlapping: the top bar, the picture (it shrinks first), the speed
    /// bar, and the instruction card in space of its own that nothing is drawn over.
    private var scanBody: some View {
        ScanLayoutView {
            // Above the picture for touches too, whatever the picture does.
            topLine.zIndex(1)
        } picture: {
            picture
        } bottom: {
            bottom
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

    /// Setup: "Step 2 of 4: Find the eyepiece" and More. The scan: the organism total, "Column 3 of
    /// 9" and a small End run.
    private var topLine: some View {
        HStack {
            if hasStarted {
                Text(LiveCountInfo.organisms(model.countInfo.total)).bold()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Text(columnText).bold()
                Button {
                    showsDetections.toggle()
                } label: {
                    Image(systemName: showsDetections ? "eye.fill" : "eye")
                }
                .accessibilityLabel("Show detections")
                .accessibilityValue(showsDetections ? "On" : "Off")
                Menu {
                    ForEach(
                        isAwayFromPath
                            ? EndRunMenu.awayItems
                            : EndRunMenu.items(
                                columnInProgress: model.runControl.columnInProgress
                                    && !isFixedSweep,
                                endingAfterColumn: endsAfterColumn), id: \.title
                    ) { item in
                        Button(item.title, role: item == .endNow ? .destructive : nil) {
                            chooseEnd(item)
                        }
                    }
                } label: {
                    Text(EndRunMenu.label(endingAfterColumn: endsAfterColumn))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(.bordered).controlSize(.small).tint(.white)
                .disabled(model.runControl.isFinished)
            } else {
                Text(setupTitle).bold().lineLimit(1).minimumScaleFactor(0.7)
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
        }
        .font(.headline.monospacedDigit())
        .padding(.horizontal)
        .padding(.vertical, 8)
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
                if model.isAnalyzing {
                    overlays(display: display, isCentred: isCentred)
                } else {
                    ProgressView("Starting the camera…").tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(Rectangle())
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
        .clipped()
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
                if model.setupInfo.isAlignmentPassed, !isSetupHeld {
                    confirmPanel(
                        question: "Is the phone aligned?",
                        detail: "The whole round view is in the picture, round and evenly lit.")
                }
            case .focus:
                darkOutside(info, converter, isCentred)
                LiveSetupOverlay(
                    model: model, previewLayer: previewLayer, showsIndicator: false, display: display)
                if model.setupInfo.focus?.state == .focused {
                    confirmPanel(
                        question: "Is the picture sharp?",
                        detail: "Best focus found. Keep the knob still and confirm.")
                }
            case .field:
                LiveFieldOutlines(
                    model: model, previewLayer: previewLayer, display: display,
                    darkensOutside: false)
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
                darkOutside(info, converter, isCentred)
                GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                // The eye button, or the organisms seen while steering by hand (not counted).
                if showsDetections || model.handHold == .on {
                    LiveDetectionBoxes(model: model, converter: converter)
                }
                if hasStarted {
                    LiveGuideOverlay(
                        state: model.overlayState, plain: true,
                        hidesMark: session.display?.questionID != nil)
                    EdgeLineOverlay(state: model.edgeLineState, mapper: converter)
                    PausedOverlay(
                        monitor: model.setupInfo.monitor, mapper: converter,
                        onResumeAnyway: nil)
                    // The lab's speed bar, where the lab draws it: bottom left of the picture.
                    VStack {
                        Spacer()
                        HStack {
                            LiveSpeedMeter(model: model).frame(width: 140)
                            Spacer()
                        }
                    }
                    .padding(8)
                    .allowsHitTesting(false)
                }
            }
        }
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
            scanBottom
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
                StageModeChoiceView(
                    selection: $modeChoice, objective: $objective, control: $controlChoice,
                    onContinue: continueFromChoice)
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
            if stage == .ready {
                CoverageChoiceView(coverage: $coverage)
                recordVideoToggle
                bigButton("Start scan", action: startScan)
            }
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
            onRetry: { driver.recalibrate() }, onResume: { driver.resume() },
            onFocused: { driver.focusIsSharp() },
            onBackToManual: driver.canBackToManual ? { driver.backToManual() } : nil)
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
            case .stage:
                calibrationCard(driver)
            case .ready where !driver.isCalibrated:
                // "Skip setup" jumps over the stage step: the stage measures itself here.
                calibrationCard(driver)
            case .ready:
                StagePathChoiceView(pathMode: $pathChoice, coverage: $coverage, objective: objective)
                recordVideoToggle
                let isConnected = driver.client.status == .connected
                bigButton("Start scan", isEnabled: isConnected, action: startScan)
                if !isConnected {
                    Text("Waiting for the stage to reconnect…")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if driver.canBackToManual {
                    bigButton("Back to manual", isProminent: false) { driver.backToManual() }
                }
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
            }
            }
        }
    }

    // MARK: The Terraloka Stage

    private var isTerraloka: Bool {
        if case .terraloka = stageMode { return true }
        return false
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

    /// The Fixed sweep: the stage's own columns, not the guide's.
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
        case .endNow, .keepScanning: break
        }
        if let action = item.action { model.endRun(action) }
    }

    /// Begins the scan: logging is on for every guided scan (the movement CSV and the run
    /// record), then Mark start, as the lab's buttons do.
    private func startScan() {
        if driver?.controlMode == .manual { return }  // a look never becomes a run
        details.recordedAt = .now
        if let driver, case .terraloka = stageMode {
            driver.setPathMode(pathChoice)
            // The Fixed sweep covers the stage's own range: the run ends when the stage's path
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

    /// The instruction card, in space of its own. The speed is the lab's bar on the picture.
    private var scanBottom: some View {
        VStack(spacing: 8) {
            if let driver, isTerraloka, driver.phase == .byHand {
                // The pad takes the status card's place; the organisms show as not counted.
                StageHandPad(driver: driver, isCompact: true)
                Button("Go back and resume") { driver.goBackAndResume() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            } else if let driver, isTerraloka {
                StageRunStatusCard(
                    status: driver.status, isPaused: driver.phase == .paused,
                    progress: driver.pathMode == .presetPath
                        ? driver.presetProgress ?? StageZigzagProgress() : nil,
                    actions: driver.status.needsPerson.map { alertActions($0, driver) } ?? [],
                    onPause: { driver.pause() }, onResume: { driver.resume() },
                    canMoveManually: driver.canMoveByHand,
                    onMoveManually: { driver.beginHandControl() },
                    hasSavedPosition: driver.handSaved != nil && driver.canGoBack,
                    onGoBack: { driver.goBackAndResume() })
            } else {
                manualScanCard
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
