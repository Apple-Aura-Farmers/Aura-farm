#if DEBUG
    import AVFoundation
    import SwiftUI

    /// Measures how well the app can track a slide moved by hand, and how blank glass differs
    /// from blur. Debug builds only, and nothing to do with a sweep: it records numbers for
    /// the team to send back, and saves nothing to tests.
    struct SlideMovementLabView: View {
        private enum Mode: String, CaseIterable, Identifiable {
            case live = "Live camera"
            case video = "Recorded video"
            var id: String { rawValue }
        }

        @State private var model = SlideMovementLabModel()
        @State private var mode = Mode.live
        @AppStorage("slideLab.mapping") private var mappingName = ScreenMapping.rotateRight.rawValue
        @AppStorage("slideLab.mirror") private var mirrored = false
        @State private var isAskingDistance = false
        @State private var distanceText = ""
        @State private var isShowingTrail = false
        @State private var previewLayer: AVCaptureVideoPreviewLayer?
        @AppStorage("slideLab.showsSees") private var showsSees = false
        @AppStorage("slideLab.fieldRegion") private var fieldRegionName = FieldRegionMode.auto.rawValue
        @AppStorage("slideLab.hopAgreement") private var hopAgreement = false
        @AppStorage("slideLab.guideDryRun") private var guideDryRun = false
        @AppStorage("slideLab.centreField") private var centresField = true
        @AppStorage("slideLab.straighten") private var straightens = true
        @AppStorage("slideLab.pauseOnMonitor") private var pausesOnMonitor = true
        @AppStorage("slideLab.showEdgeLine") private var showsEdgeLine = true
        @AppStorage("slideLab.trackSparse") private var tracksSparse = true
        @AppStorage("slideLab.fullCoverSlip") private var fullCoverSlip = true
        @AppStorage("slideLab.askEdges") private var asksEdges = true
        @AppStorage("slideLab.followSlipTilt") private var followsSlipTilt = true
        @AppStorage("slideLab.showLifeOnMap") private var showsLifeOnMap = true
        // The guided scan page's knob rule, for other microscopes. See `KnobRule`.
        @AppStorage("slideLab.knobSwap") private var swapsKnobs = false
        @AppStorage("slideLab.knobReverseX") private var reversesKnobX = false
        @AppStorage("slideLab.knobReverseY") private var reversesKnobY = false
        @AppStorage("slideLab.coverSlipShape") private var coverSlipName = CoverSlipShape.square.rawValue
        @AppStorage("slideLab.skipAlignFocus") private var skipsAlignFocus = false
        @AppStorage("slideLab.spotMode") private var spotModeName = "briefTouch"
        @AppStorage("slideLab.coverageStep") private var coverageStep = 0.8
        @AppStorage("slideLab.countOrganisms") private var countsOrganisms = true
        @AppStorage("slideLab.showDetections") private var showsDetections = false
        @AppStorage("slideLab.cropEyepiece") private var cropsToEyepiece = true
        @AppStorage("slideLab.detectorModel") private var detectorModelName = DetectorModel.v3.rawValue
        @AppStorage("slideLab.detectorUnits") private var detectorUnitsName = DetectorUnits.neuralEngine
            .rawValue
        @AppStorage("slideLab.cameraRate") private var cameraRateName = CameraRate.fps20.rawValue
        @AppStorage("slideLab.confidence") private var confidence = 0.3
        @AppStorage("slideLab.heatAdaptive") private var heatAdaptive = true
        @AppStorage("slideLab.modelRateCap") private var modelRateCap = true
        @AppStorage("slideLab.recordLensVideo") private var recordsLensVideo = false
        /// Labels and sweeps for the focus data (measured and logged only).
        @AppStorage("slideLab.focusTest") private var focusTest = false
        @State private var noteText = ""
        // Automated stage (Terraloka BLE stage in place of the knobs).
        @State private var autoStage: AutoStageDriver?
        /// "How will the slide move?" card, shown until a choice is made.
        @State private var needsMovementChoice = true
        @State private var isShowingStageSheet = false
        @State private var isChoosingAutonomousPath = false
        @Environment(\.scenePhase) private var scenePhase
        /// Waiting for the stage's Bluetooth connection; setup is held while it does, if it
        /// has not got past Align.
        @State private var isWaitingForStage = false
        @State private var holdsSetupForStage = false

        // Recorded video.
        @State private var selectedVideo: URL?
        @State private var startMinutes = 0.0

        private var mapping: ScreenMapping { ScreenMapping(rawValue: mappingName) ?? .asIs }

        /// Turns the Terraloka stage in or out; with it off the lab behaves as it always has. Turning
        /// it on opens the "Automated stage" sheet, which starts it.
        private func setAutomatedStage(_ on: Bool) {
            if on {
                needsMovementChoice = false
                if autoStage == nil { isShowingStageSheet = true }
            } else if let driver = autoStage {
                driver.deactivate()
                autoStage = nil
                endWaitingForStage()
            }
        }

        /// The connection is made, or the automated stage was cancelled: setup goes on.
        private func endWaitingForStage() {
            isWaitingForStage = false
            if holdsSetupForStage {
                holdsSetupForStage = false
                model.setSetupHeld(false)
            }
        }

        private func startAutomatedStage(
            _ objective: StageObjective, _ pathMode: StagePathMode, _ control: StageControlMode
        ) {
            guard autoStage == nil else { return }
            let driver = AutoStageDriver(engine: model)
            driver.controlMode = control
            driver.objective = objective
            driver.chunkDegrees = objective.defaultChunk
            driver.pathMode = pathMode
            driver.guideIsStraightened = straightens && centresField
            driver.activate(restoringAsksEdges: asksEdges)
            autoStage = driver
            // Setup waits for the connection; a lab already past Align is not sent back.
            isWaitingForStage = true
            if model.setupInfo.step == .align {
                holdsSetupForStage = true
                model.setSetupHeld(true)
            }
        }

        private var spotMode: SpotConfirmMode { spotModeName == "holdStill" ? .holdStill : .briefTouch }

        var body: some View {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                if needsMovementChoice, mode == .live {
                    MovementChoiceCard(
                        onManual: { needsMovementChoice = false },
                        onAutomated: { setAutomatedStage(true) })
                }
                if isWaitingForStage, let autoStage, mode == .live {
                    StageConnectingCard(
                        client: autoStage.client.status, backTitle: "Cancel",
                        onRetry: { autoStage.client.connect() },
                        onBack: { setAutomatedStage(false) }
                    )
                    .padding(.horizontal)
                }
                if let autoStage, mode == .live {
                    AutoStagePanel(
                        driver: autoStage, setupStep: model.setupInfo.step,
                        onSwitchToAutonomous: { isChoosingAutonomousPath = true })
                }

                switch mode {
                case .live: liveBody
                case .video: videoBody
                }
            }
            .navigationTitle("Slide movement lab")
            .navigationBarTitleDisplayMode(.inline)
            // The same settings sequence and syncs the guided scan page uses.
            .modifier(
                LabSettingsSync(model: model) { if mode == .live { model.start() } }
            )
            .onDisappear {
                model.stop()
                setAutomatedStage(false)
            }
            .onChange(of: scenePhase) { _, phase in
                // Nothing keeps moving behind the person's back.
                guard phase == .background, let autoStage else { return }
                if autoStage.phase == .byHand {
                    autoStage.handStop()
                } else if case .returningFromHand = autoStage.phase {
                    autoStage.pause()
                }
            }
            .confirmationDialog(
                "Switch to autonomous?", isPresented: $isChoosingAutonomousPath,
                titleVisibility: .visible
            ) {
                Button("Follow guide") { autoStage?.switchToAutonomous(.followGuide) }
                Button("Preset path") { autoStage?.switchToAutonomous(.presetPath) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The stage goes to its centre, warms up and calibrates, then starts moving by itself.")
            }
            .sheet(isPresented: $isShowingStageSheet) {
                AutomatedStageSheet(onStart: startAutomatedStage)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Toggle(
                        "Terraloka",
                        isOn: Binding(get: { autoStage != nil }, set: { setAutomatedStage($0) })
                    )
                    .toggleStyle(.button)
                    .font(.footnote)
                }
            }
            .onChange(of: autoStage?.client.status) { _, status in
                if status == .connected, isWaitingForStage { endWaitingForStage() }
            }
            .onChange(of: straightens && centresField) { _, value in
                autoStage?.guideIsStraightened = value
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .live { model.start() } else { model.stop() }
            }
            .alert("Distance moved", isPresented: $isAskingDistance) {
                TextField("mm", text: $distanceText)
                    .keyboardType(.decimalPad)
                Button("Mark end") {
                    model.markEnd(millimetres: Double(distanceText.replacingOccurrences(of: ",", with: ".")))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Read it off the stage's vernier scale, in millimetres. For the landmark test, leave this empty."
                )
            }
        }

        // MARK: Live camera

        private static let lensID = "lens"
        private var isManual: Bool { autoStage?.phase == .byHand }

        private var liveBody: some View {
            ScrollViewReader { scroller in
                liveScroll
                    // The picture and the arrows are on screen together.
                    .onChange(of: isManual) { _, manual in
                        if manual { withAnimation { scroller.scrollTo(Self.lensID, anchor: .top) } }
                    }
            }
            .toolbarVisibility(isManual ? .hidden : .automatic, for: .tabBar)
        }

        private var liveScroll: some View {
            ScrollView {
                VStack(spacing: 0) {
                    testPicker
                    GeometryReader { proxy in
                        // The picture as the field's square: one transform for the preview and
                        // the converter every frame-anchored mark goes through, the circle
                        // centred, filling the width and straightened by the stage's axes.
                        // Uncropped until the field is confirmed, and when the toggle is off.
                        let isCentred =
                            centresField && model.isAnalyzing
                            && (model.setupInfo.step == .focus || model.setupInfo.step == .stage
                                || model.setupInfo.step == .done)
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
                                    // The whole frame is kept: with aspect fill a circle away from
                                    // the middle has part of its square outside what is drawn.
                                    $0.videoGravity = .resizeAspect
                                    previewLayer = $0
                                }
                            )
                            .transformEffect(display)
                            if model.isAnalyzing {
                                SlideMovementOverlays(
                                    model: model, mapping: mapping, mirrored: mirrored,
                                    previewLayer: previewLayer, display: display, centred: isCentred,
                                    onTapTrail: { isShowingTrail = true },
                                    onEmptyArea: autoStage?.canConfirmEmptyArea == true
                                        ? { autoStage?.confirmEmptyArea() } : nil,
                                    automatedStage: autoStage != nil)
                            } else {
                                startingCard
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(Rectangle())
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .id(Self.lensID)

                    // Under the picture, never over it: the person steers by what they see.
                    if let autoStage, isManual {
                        StageHandPad(
                            driver: autoStage, needsGuideDryRun: !model.guideDryRun,
                            onSwitchToAutonomous: { isChoosingAutonomousPath = true })
                    }

                    if focusTest, model.setupInfo.step == .done {
                        FocusTestSection(model: model)
                    }

                    if model.isAnalyzing, isSettingUp {
                        alignFocusControls
                    } else if model.isAnalyzing {
                        if showsSees { seesThumbnail }
                        BigReadouts(model: model)
                        if model.guideDryRun { GuideReadout(model: model) }
                        if model.guideDryRun, showsDetections { DetectionPanel(info: model.countInfo) }
                        analyzingControls
                    } else {
                        setupControls
                    }
                }
            }
            .background(SlideLabHaptics(model: model))
            .sheet(isPresented: $isShowingTrail) { fullTrail }
            .sheet(
                isPresented: Binding(
                    get: { model.runSummary != nil }, set: { if !$0 { model.dismissSummary() } })
            ) {
                if let record = model.runSummary {
                    RunSummaryCard(
                        record: record, shareItems: model.summaryItems,
                        videoNote: model.lensVideoNote,
                        onDone: { model.dismissSummary() }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
        }

        /// "What the app sees": the grid the analysis uses, in the frame's raw orientation.
        private var seesThumbnail: some View {
            VStack(spacing: 2) {
                if let image = model.thumbnailImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 240)
                } else {
                    Text("Waiting for a frame…").font(.caption)
                }
                Text(
                    "Raw frame as analysed (not rotated). Red = treated as eyepiece. Yellow = where movement is measured."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal)
            .padding(.top, 4)
        }

        /// Align and focus: nothing is learned or tracked, so only the setup's own controls.
        private var isSettingUp: Bool {
            model.setupInfo.step == .align || model.setupInfo.step == .focus
        }

        /// Shown over the camera for the moment before the session's setup begins.
        private var startingCard: some View {
            ProgressView("Starting the camera…")
                .tint(.white)
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
        }

        /// While aligning and focusing: the phone's own Focus slider stays hidden, so it cannot
        /// be mistaken for the microscope's focus knob (the lens stays locked).
        private var alignFocusControls: some View {
            VStack(alignment: .leading, spacing: 16) {
                cameraProblem
                Text(
                    model.setupInfo.step == .align
                        ? "1. Align the phone: the whole microscope circle in view, round, evenly lit, no glare."
                        : "3. Focus with the microscope's focus knob (the stage's Z), not the phone's."
                )
                .font(.callout)
                if model.setupInfo.step == .focus {
                    Button("It's sharp, continue") { model.acceptFocus() }.buttonStyle(.bordered)
                }
                setupButtons
                footer
            }
            .padding()
        }

        /// Redo setup, the skip option and the setup log.
        private var setupButtons: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Redo setup") { model.redoSetup() }
                    Button("Export setup log") { model.exportSetupLog() }
                    if let url = model.setupLogURL {
                        ShareLink("Share setup log", item: url)
                    }
                }
                .buttonStyle(.bordered)
                Toggle("Skip align and focus", isOn: $skipsAlignFocus)
                Text("Skipping starts the next session at the field step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        /// Before Start: only what is needed to place and focus the phone.
        private var setupControls: some View {
            VStack(alignment: .leading, spacing: 16) {
                cameraProblem
                focusSlider
                Text(
                    "Tapping Start learns the eyepiece mask afresh, so set the phone and the light first."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                footer
            }
            .padding()
        }

        private var analyzingControls: some View {
            VStack(alignment: .leading, spacing: 16) {
                cameraProblem
                mappingControls
                TextReadout(model: model)
                settingsControls
                // The phone's own focus is for the field step on; the microscope's comes first.
                focusSlider
                labelButtons
                actionButtons
                StatisticsTable(model: model)
                notesField
                footer
            }
            .padding()
        }

        @ViewBuilder
        private var cameraProblem: some View {
            if let problem = model.cameraError {
                Text(problem).foregroundStyle(.red)
            } else if model.authorization == .denied {
                Text("Camera access is off. Turn it on in Settings.")
                    .foregroundStyle(.red)
            }
        }

        private var testPicker: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Test").font(.subheadline.bold())
                    Picker(
                        "Test",
                        selection: Binding(get: { model.test }, set: { model.setTest($0) })
                    ) {
                        ForEach(SlideLabTest.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.test.instruction).font(.callout)
                    Text(
                        "1 field = the side of the yellow box, about the width of the useful view. Count grid squares on the trail, or watch the “fields” number."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
        }

        private var mappingControls: some View {
            HStack {
                Picker("Mapping", selection: $mappingName) {
                    ForEach(ScreenMapping.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                Toggle("Mirror", isOn: $mirrored)
                    .fixedSize()
                Spacer()
                let size = model.readouts.frameSize
                Text("\(Int(size.width)) x \(Int(size.height))")
                    .font(.caption.monospaced())
            }
        }

        private var fullTrail: some View {
            NavigationStack {
                VStack(spacing: 12) {
                    LiveTrail(model: model, mapping: mapping, mirrored: mirrored)
                        .aspectRatio(1, contentMode: .fit)
                        .padding()
                    mappingControls.padding(.horizontal)
                    Spacer()
                }
                .navigationTitle("Trail")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Close") { isShowingTrail = false }
                    }
                }
            }
        }

        /// Where movement is registered, and whether hops are checked for agreement.
        private var settingsControls: some View {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Field region", selection: $fieldRegionName) {
                    ForEach(FieldRegionMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.menu)
                HStack {
                    Button("Re-detect field") { model.redetectField() }
                        .disabled(!(FieldRegionMode(rawValue: fieldRegionName)?.learnsMask ?? true))
                }
                .buttonStyle(.bordered)
                setupButtons
                Toggle("Show what the app sees", isOn: $showsSees)
                Toggle("Measure hop agreement", isOn: $hopAgreement)
                Toggle("Guide dry run", isOn: $guideDryRun)
                Toggle("Centre the field", isOn: $centresField)
                Toggle("Straighten picture", isOn: $straightens)
                Toggle("Pause when out of focus or alignment", isOn: $pausesOnMonitor)
                Toggle("Show edge line", isOn: $showsEdgeLine)
                Toggle("Track sparse sample", isOn: $tracksSparse)
                Toggle("Full cover slip (line edges)", isOn: $fullCoverSlip)
                Toggle("Ask me to confirm edges", isOn: $asksEdges)
                Toggle("Columns follow the slip's tilt", isOn: $followsSlipTilt)
                Toggle("Show life on map", isOn: $showsLifeOnMap)
                Toggle("Record lens video", isOn: $recordsLensVideo)
                Toggle("Focus test (labels and sweeps)", isOn: $focusTest)
                Toggle("Swap knobs", isOn: $swapsKnobs)
                Toggle("Reverse X", isOn: $reversesKnobX)
                Toggle("Reverse Y", isOn: $reversesKnobY)
                Text(
                    "Knob words on the guided scan page: X is the bottom knob. Arrow left = towards you, right = away; up = top knob towards you, down = away."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                CoverSlipPicker(name: $coverSlipName)
                Picker("Spot check", selection: $spotModeName) {
                    Text("Brief touch").tag("briefTouch")
                    Text("Hold still").tag("holdStill")
                }
                .pickerStyle(.segmented)
                Picker("Coverage", selection: $coverageStep) {
                    Text("Every column").tag(0.8)
                    Text("Every 2nd").tag(1.6)
                    Text("Every 3rd").tag(2.4)
                }
                .pickerStyle(.segmented)
                Picker("Model", selection: $detectorModelName) {
                    ForEach(DetectorModel.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(model.modelLocked)
                Picker("Model chip", selection: $detectorUnitsName) {
                    ForEach(DetectorUnits.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(model.modelLocked)
                Picker("Camera", selection: $cameraRateName) {
                    ForEach(CameraRate.allCases) { Text($0.displayName).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .disabled(model.modelLocked)
                if !model.cameraNote.isEmpty {
                    Text(model.cameraNote).font(.caption).foregroundStyle(.secondary)
                }
                if model.modelLocked {
                    Text("The model, chip and camera can change before Mark start or after a finish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Count organisms", isOn: $countsOrganisms)
                Toggle("Show detections", isOn: $showsDetections)
                Toggle("Crop to eyepiece circle", isOn: $cropsToEyepiece)
                Toggle("Heat-adaptive mode", isOn: $heatAdaptive)
                Toggle("Cap model at 5 a second", isOn: $modelRateCap)
                VStack(alignment: .leading) {
                    Text("Confidence \(confidence, specifier: "%.2f")").font(.caption)
                    Slider(value: $confidence, in: 0.1...0.6, step: 0.05)
                }
                Text("Red tint: treated as the eyepiece. Yellow box: where movement is measured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var focusSlider: some View {
            VStack(alignment: .leading) {
                Text("Focus")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { Double(model.lensPosition) },
                        set: { model.setLensPosition(Float($0)) }),
                    in: 0...1)
            }
        }

        private var labelButtons: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Label written into each logged row")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    ForEach(
                        [("Sample", "sample"), ("Blank", "blank"), ("Blurry", "blurry"), ("None", "")],
                        id: \.0
                    ) { name, value in
                        Button(name) { model.setLabel(value) }
                            .buttonStyle(.bordered)
                            .tint(model.label == value ? slideLabLabelColor(value) : .gray)
                            .fontWeight(model.label == value ? .bold : .regular)
                    }
                }
            }
        }

        private var actionButtons: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button("Reset position") { model.resetPosition() }
                    Spacer()
                    Button("Mark start") { model.markStart() }
                        .disabled(!model.isLogging || model.setupInfo.step != .done)
                    Button("Mark end") {
                        distanceText = ""
                        isAskingDistance = true
                    }
                    .disabled(!model.isLogging)
                }
                .buttonStyle(.bordered)

                Button("Save frame") { model.saveFrame() }
                    .buttonStyle(.bordered)
                    .disabled(!model.isLogging)

                HStack {
                    if model.isLogging {
                        Button("Stop log", role: .destructive) { model.stopLog() }
                    } else {
                        Button("Start log") { model.startLog() }
                    }
                    Text("\(model.rowCount) rows")
                        .font(.footnote.monospaced())
                    Spacer()
                    if model.exportURL != nil {
                        ShareLink(
                            model.exportItems.count > 1
                                ? "Export CSV + \(model.exportItems.count - 1) frames" : "Export CSV",
                            items: model.exportItems)
                    } else {
                        Text("Export CSV").foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }

        private var notesField: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes for this log").font(.caption).foregroundStyle(.secondary)
                TextField(
                    "e.g. hand-moved, 10x objective, iPhone 15", text: $noteText
                )
                .textFieldStyle(.roundedBorder)
                .onChange(of: noteText) { _, text in model.setNote(text) }
            }
        }

        // MARK: Recorded video

        private var videoBody: some View {
            Form {
                DebugVideoPicker(selected: $selectedVideo)

                Section("Start at") {
                    Stepper(
                        "\(Int(startMinutes)) min \(Int((startMinutes - startMinutes.rounded(.down)) * 60)) s",
                        value: $startMinutes, in: 0...90, step: 0.5)
                }

                Section {
                    Button {
                        guard let selectedVideo else { return }
                        model.runVideo(url: selectedVideo, startSeconds: startMinutes * 60)
                    } label: {
                        if model.isRunningVideo {
                            HStack {
                                ProgressView()
                                Text(model.videoProgress)
                            }
                        } else {
                            Text("Run")
                        }
                    }
                    .disabled(selectedVideo == nil || model.isRunningVideo)
                }

                if let summary = model.videoSummary {
                    Section("Summary") {
                        Text(summary)
                        if let url = model.videoExportURL {
                            ShareLink("Export CSV", item: url)
                        }
                    }
                }

                Section { footer }
            }
        }

        private var footer: some View {
            Text("Measurement tool for the team. Nothing here is saved to tests.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    #Preview {
        NavigationStack { SlideMovementLabView() }
    }

    /// "Cover slip": Square (the usual 22 x 22 mm) lets the guide predict the right edge.
    struct CoverSlipPicker: View {
        @Binding var name: String

        var body: some View {
            Picker("Cover slip", selection: $name) {
                ForEach(CoverSlipShape.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
        }
    }

    private struct CoverSlipPreview: View {
        @State private var name = CoverSlipShape.square.rawValue
        var body: some View { Form { CoverSlipPicker(name: $name) } }
    }

    #Preview("Cover slip setting") { CoverSlipPreview() }

    /// Labels and sweeps for the focus data: with the log recording, a tap says what the view is
    /// (three raw frames are saved), a sweep saves a frame every half second. Logging only: it
    /// pauses, counts, moves and holds nothing.
    private struct FocusTestSection: View {
        var model: ScanEngine

        var body: some View {
            let tiles = model.setupInfo.monitor.recentFocusTiles
            VStack(alignment: .leading, spacing: 8) {
                if !model.isLogging {
                    Text("Start the log first").font(.footnote).foregroundStyle(.orange)
                }
                HStack(spacing: 8) {
                    ForEach(["sharp", "blurry", "empty"], id: \.self) { name in
                        Button {
                            model.labelFocus(name)
                        } label: {
                            Text(name.capitalized).font(.title3.bold())
                                .frame(maxWidth: .infinity, minHeight: 48)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .disabled(!model.isLogging)
                Button {
                    if model.focusSweeping { model.endFocusSweep() } else { model.startFocusSweep() }
                } label: {
                    Text(model.focusSweeping ? "End sweep" : "Start sweep")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(!model.isLogging)
                Text(
                    tiles.map {
                        String(
                            format: "top %.4g · active %d of %d · noise %.4g", $0.top, $0.active,
                            $0.used, $0.noise)
                    } ?? "no reading yet"
                )
                .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
    }

    /// The top-of-screen question that replaces the old dialog: not modal, so nothing can drop it.
    private struct MovementChoiceCard: View {
        var onManual: () -> Void
        var onAutomated: () -> Void

        var body: some View {
            VStack(spacing: 8) {
                Text("How will the slide move?").font(.subheadline.bold())
                HStack {
                    Button("Mechanical stage", action: onManual).buttonStyle(.bordered)
                    Button("Terraloka stage", action: onAutomated).buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.thinMaterial)
        }
    }

    /// The one place the objective and the path mode are chosen; both start from the last choice.
    private struct AutomatedStageSheet: View {
        var onStart: (StageObjective, StagePathMode, StageControlMode) -> Void
        @Environment(\.dismiss) private var dismiss
        @AppStorage("slideLab.stageObjective") private var objectiveName = StageObjective.x40.rawValue
        @AppStorage("slideLab.stagePathMode") private var pathModeName = StagePathMode.presetPath.rawValue
        @AppStorage("slideLab.stageControl") private var controlName = StageControlMode.autonomous.rawValue
        private var control: StageControlMode { StageControlMode(rawValue: controlName) ?? .autonomous }

        var body: some View {
            NavigationStack {
                Form {
                    Picker(
                        "Control",
                        selection: Binding(get: { control }, set: { controlName = $0.rawValue })
                    ) {
                        Text("Manual").tag(StageControlMode.manual)
                        Text("Autonomous").tag(StageControlMode.autonomous)
                    }
                    .pickerStyle(.segmented)
                    Picker(
                        "Objective",
                        selection: Binding(
                            get: { StageObjective(rawValue: objectiveName) ?? .x40 },
                            set: { objectiveName = $0.rawValue })
                    ) {
                        ForEach(StageObjective.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if control == .autonomous {
                        Picker(
                            "Path",
                            selection: Binding(
                                get: { StagePathMode(rawValue: pathModeName) ?? .presetPath },
                                set: { pathModeName = $0.rawValue })
                        ) {
                            ForEach(StagePathMode.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Text("No calibration: you steer with the arrows. You can switch to autonomous later.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Terraloka stage")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Start") {
                            onStart(
                                StageObjective(rawValue: objectiveName) ?? .x40,
                                StagePathMode(rawValue: pathModeName) ?? .presetPath, control)
                            dismiss()
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }
#endif
