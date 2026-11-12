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
        @AppStorage("slideLab.mapping") private var mappingName = ScreenMapping.asIs.rawValue
        @AppStorage("slideLab.mirror") private var mirrored = false
        @State private var isAskingDistance = false
        @State private var distanceText = ""
        @State private var isShowingTrail = false
        @State private var previewLayer: AVCaptureVideoPreviewLayer?
        @AppStorage("slideLab.showsSees") private var showsSees = false
        @AppStorage("slideLab.fieldRegion") private var fieldRegionName = FieldRegionMode.auto.rawValue
        @AppStorage("slideLab.hopAgreement") private var hopAgreement = false
        @AppStorage("slideLab.guideDryRun") private var guideDryRun = false
        @State private var noteText = ""

        // Recorded video.
        @State private var selectedVideo: URL?
        @State private var startMinutes = 0.0

        private var mapping: ScreenMapping { ScreenMapping(rawValue: mappingName) ?? .asIs }

        var body: some View {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .live: liveBody
                case .video: videoBody
                }
            }
            .navigationTitle("Slide movement lab")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                model.setFieldRegion(FieldRegionMode(rawValue: fieldRegionName) ?? .auto)
                model.setMeasuresHopAgreement(hopAgreement)
                model.setShowsThumbnail(showsSees)
                model.setGuideDryRun(guideDryRun)
                model.setScreenMapping(mapping, mirrored: mirrored)
                if mode == .live { model.start() }
            }
            .onChange(of: fieldRegionName) { _, name in
                model.setFieldRegion(FieldRegionMode(rawValue: name) ?? .auto)
            }
            .onChange(of: hopAgreement) { _, enabled in model.setMeasuresHopAgreement(enabled) }
            .onChange(of: showsSees) { _, shown in model.setShowsThumbnail(shown) }
            .onChange(of: guideDryRun) { _, enabled in model.setGuideDryRun(enabled) }
            .onChange(of: mappingName) { model.setScreenMapping(mapping, mirrored: mirrored) }
            .onChange(of: mirrored) { model.setScreenMapping(mapping, mirrored: mirrored) }
            .onDisappear { model.stop() }
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

        private var liveBody: some View {
            ScrollView {
                VStack(spacing: 0) {
                    testPicker
                    ZStack {
                        CameraPreview(session: model.session, onLayer: { previewLayer = $0 })
                        if model.isAnalyzing {
                            SlideMovementOverlays(
                                model: model, mapping: mapping, mirrored: mirrored,
                                previewLayer: previewLayer, onTapTrail: { isShowingTrail = true })
                        } else {
                            setupCard
                        }
                    }
                    .frame(height: 440)
                    .clipped()

                    if model.isAnalyzing {
                        if showsSees { seesThumbnail }
                        BigReadouts(model: model)
                        if model.guideDryRun { GuideReadout(model: model) }
                        analyzingControls
                    } else {
                        setupControls
                    }
                }
            }
            .background(SlideLabHaptics(model: model))
            .sheet(isPresented: $isShowingTrail) { fullTrail }
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

        /// Shown over the camera until Start: nothing is measured while the phone is set up.
        private var setupCard: some View {
            VStack(spacing: 10) {
                Text("Set up the phone").font(.headline)
                Text("Position it over the eyepiece and focus with the slider below.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                Button {
                    model.beginAnalysis()
                } label: {
                    Text("Start")
                        .font(.title3.bold())
                        .padding(.horizontal, 32)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
            .foregroundStyle(.white)
            .padding(16)
            .frame(maxWidth: 280)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
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
                    Button("Back to setup") { model.endAnalysis() }
                }
                .buttonStyle(.bordered)
                Toggle("Show what the app sees", isOn: $showsSees)
                Toggle("Measure hop agreement", isOn: $hopAgreement)
                Toggle("Guide dry run", isOn: $guideDryRun)
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
                        .disabled(!model.isLogging)
                    Button("Mark end") {
                        distanceText = ""
                        isAskingDistance = true
                    }
                    .disabled(!model.isLogging)
                }
                .buttonStyle(.bordered)

                HStack {
                    if model.isLogging {
                        Button("Stop log", role: .destructive) { model.stopLog() }
                    } else {
                        Button("Start log") { model.startLog() }
                    }
                    Text("\(model.rowCount) rows")
                        .font(.footnote.monospaced())
                    Spacer()
                    if let url = model.exportURL {
                        ShareLink("Export CSV", item: url)
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
#endif
