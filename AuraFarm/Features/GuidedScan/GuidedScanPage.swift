import AVFoundation
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
    @State private var saveProblem: String?
    @State private var haptics = HelperHapticPlayer()
    // The lab's own display settings.
    @AppStorage("slideLab.centreField") private var centresField = true
    @AppStorage("slideLab.straighten") private var straightens = true

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
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog(
                "Stop this scan?", isPresented: $isConfirmingLeave, titleVisibility: .visible
            ) {
                Button("Stop and discard", role: .destructive) {
                    model.stop()
                    dismiss()
                }
                Button("Keep scanning", role: .cancel) {}
            } message: {
                Text("Nothing is saved unless you use End run.")
            }
            // The lab's settings sequence and syncs, and its start: model.start() on open.
            .modifier(
                LabSettingsSync(
                    model: model,
                    transform: { $0.forGuidedScan(coverage: coverage.rawValue) },
                    onReady: {
                        // Align and focus wait for a Confirm tap, like the field review.
                        model.setConfirmsSetupSteps(true)
                        model.start()
                    })
            )
            .onDisappear { model.stop() }
            .alert(
                "The scan could not be saved", isPresented: .constant(saveProblem != nil)
            ) {
                Button("OK") { saveProblem = nil }
            } message: {
                Text(saveProblem ?? "")
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
        .background(GuidedScanHaptics(model: model, session: session, player: haptics))
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
                Text(session.display?.columnText ?? "").bold()
                Button {
                    showsDetections.toggle()
                } label: {
                    Image(systemName: showsDetections ? "eye.fill" : "eye")
                }
                .accessibilityLabel("Show detections")
                .accessibilityValue(showsDetections ? "On" : "Off")
                Menu {
                    ForEach(
                        EndRunMenu.items(
                            columnInProgress: model.runControl.columnInProgress,
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
                Text(stage.indicator).bold().lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
                Menu("More", systemImage: "ellipsis.circle") {
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
                if model.setupInfo.isAlignmentPassed {
                    confirmPanel(
                        question: "Is the phone aligned?",
                        detail: "The whole round view is in the picture, round and evenly lit.")
                }
            case .focus:
                LiveSetupOverlay(model: model, previewLayer: previewLayer, showsIndicator: false)
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
                LiveSetupOverlay(model: model, previewLayer: previewLayer, showsIndicator: false)
            case .ready:
                darkOutside(info, converter, isCentred)
                GuideGeometryHost(model: model, previewLayer: previewLayer, display: display)
                if hasStarted {
                    if showsDetections {
                        LiveDetectionBoxes(model: model, converter: converter)
                    }
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
    /// coverage and Start scan once setup is done.
    private var setupBottom: some View {
        VStack(spacing: 10) {
            if let problem = cameraProblem {
                Text(problem).font(.subheadline).foregroundStyle(.red)
            }
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
                bigButton("Start scan", action: startScan)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func bigButton(
        _ title: String, isEnabled: Bool = true, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title).font(.title2.bold()).frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
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
        details.recordedAt = .now
        session.start(coverage: coverage, rule: GuidedScanSettings.knobRule)
        hasStarted = true
        model.startLog()
        model.markStart()
    }

    /// The instruction card, in space of its own. The speed is the lab's bar on the picture.
    private var scanBottom: some View {
        VStack(spacing: 8) {
            HelperCardView(
                card: session.display?.card ?? .waiting("Getting ready…"),
                onYes: { haptics.play(session.answer(.yes, on: model)) },
                onNo: { haptics.play(session.answer(.no, on: model)) })
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
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
            let name = try GuidedScanSaver.save(details: details, record: record, movementCSV: csv)
            model.stop()
            onSaved(name)
            dismiss()
        } catch {
            saveProblem = error.localizedDescription
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

    var body: some View {
        // The overlay changes about ten times a second; each change is one reading.
        Color.clear
            .onChange(of: model.overlayState.model) {
                player.play(session.refresh(from: model))
            }
    }
}

#Preview("Coverage choice") {
    @Previewable @State var coverage = GuidedScanCoverage.everySecondColumn
    CoverageChoiceView(coverage: $coverage).padding().background(.black).foregroundStyle(.white)
}
