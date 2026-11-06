import AVFoundation
import SwiftUI

/// Camera preview with a live quality check, and the sweep that keeps still frames.
/// Frames are only kept when the image is good.
///
/// The preview fills the screen, with everything outside a circle in the middle greyed down,
/// because that is what the phone sees down a microscope eyepiece: a round field with the dark
/// barrel around it. The ring of ticks around the field fills up as frames are kept, so the
/// helper can see how far along the sweep is without reading anything.
struct CaptureView: View {
    @State private var model = CaptureViewModel()
    /// Live numbers, from the options menu. Used to calibrate thresholds.
    @State private var showNumbers = false
    /// Preview only: frames are always saved in colour, grayscale comes later in the pipeline.
    @State private var showGrayscale = false
    @State private var showDetails = false
    @Environment(\.dismiss) private var dismiss
    /// Owned by the setup screen, so the field number it counts up survives leaving the camera.
    @Binding var details: SampleDetails

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreview(session: model.session, boxes: model.countedBoxes)
                .grayscale(showGrayscale ? 1 : 0)
                .ignoresSafeArea()

            fieldOverlay

            VStack(spacing: 16) {
                Spacer(minLength: 0)
                caption
                if showNumbers { numbersReadout }
                focusSlider
                captureButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .preferredColorScheme(.dark)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { title }
            ToolbarItem(placement: .topBarTrailing) { optionsMenu }
        }
        .sheet(isPresented: $showDetails) {
            NavigationStack {
                SampleDetailsView(details: $details)
                    .navigationTitle("Sample details")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showDetails = false }
                                .disabled(!details.isComplete)
                        }
                    }
            }
        }
        .onAppear {
            model.start()
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        // A saved sweep means this field is done: count up and go back to the menu,
        // where the frames can be looked through.
        .onChange(of: model.recorder.lastSavedName) { _, saved in
            guard saved != nil else { return }
            details.field += 1
            dismiss()
        }
        // Buzz when a new problem appears.
        .sensoryFeedback(trigger: model.topIssue) { _, new in
            new == nil ? nil : .warning
        }
    }

    private var title: some View {
        VStack(spacing: 1) {
            Text(details.sampleID.isEmpty ? "Untitled" : details.sampleID)
                .font(.headline)
            Text(
                "Field \(details.field) · \(details.recordedAt.formatted(date: .abbreviated, time: .omitted))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Viewfinder

    /// The round field, laid over the full-screen preview. Everything outside the circle is
    /// greyed down, the way the view down an eyepiece looks, and the ring and the instruction
    /// sit on top of it.
    private var fieldOverlay: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) - 104
            ZStack {
                Color.black.opacity(0.8)
                    // The circle punches a hole in the grey, so the preview shows through it.
                    .mask {
                        Rectangle()
                            .overlay {
                                Circle()
                                    .frame(width: diameter, height: diameter)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                    }
                // The field itself is dimmed while there is something to say, so the words
                // carry over the image.
                if hint != nil {
                    Circle()
                        .fill(.black.opacity(0.45))
                        .frame(width: diameter, height: diameter)
                }
                SweepRing(fraction: ringFraction, diameter: diameter + 56)
                if let hint { hintOverlay(hint) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ringLabel)
    }

    /// How much of the ring is filled in: the share of the sweep's frames already kept.
    private var ringFraction: Double {
        model.recorder.isSweeping ? model.sweepProgress.fraction : 0
    }

    private var ringLabel: String {
        guard model.recorder.isSweeping else { return hint?.text ?? "Ready" }
        let progress = model.sweepProgress
        return "\(progress.kept) of \(progress.total) frames saved. \(hint?.text ?? "")"
    }

    private func hintOverlay(_ hint: Hint) -> some View {
        VStack(spacing: 10) {
            Image(systemName: hint.systemImage)
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
            Text(hint.text)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 44)
    }

    /// The one thing to do right now, in a field helper's words.
    private struct Hint {
        var systemImage: String
        var text: String
    }

    private var hint: Hint? {
        if model.authorization == .denied || model.authorization == .restricted {
            return Hint(
                systemImage: "camera.fill",
                text: "Camera is off. Allow camera access in Settings.")
        }
        if let error = model.cameraError {
            return Hint(systemImage: "exclamationmark.triangle.fill", text: error)
        }
        // While a sweep is paused the helper needs to see what to fix, not which way to move.
        if let issue = model.topIssue, FrameSweep.blocksCapture(issue) || !model.recorder.isSweeping {
            return Hint(systemImage: issue.systemImage, text: "\(issue.title). \(issue.advice)")
        }
        if model.recorder.isSweeping {
            return Hint(
                systemImage: model.sweepPrompt.systemImage, text: model.sweepPrompt.title)
        }
        if !model.isReady {
            return Hint(systemImage: "hourglass", text: "Checking the image. Hold still.")
        }
        return nil
    }

    /// The running count, what has been found so far, and anything that went wrong.
    @ViewBuilder
    private var caption: some View {
        VStack(spacing: 4) {
            if let error = model.recorder.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            } else if model.recorder.isSweeping {
                let progress = model.sweepProgress
                Text(
                    "\(progress.kept) of \(progress.total) frames saved · row \(progress.row) of \(progress.rowCount)"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if let problem = model.countingProblem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if model.countedTotal > 0 || model.recorder.isSweeping {
                countReadout
            }
        }
    }

    /// Each organism is counted the first time it is seen and then followed as the slide
    /// moves, so passing over the same one again does not count it twice.
    private var countReadout: some View {
        VStack(spacing: 2) {
            Text("\(model.countedTotal) counted")
                .font(.title3.monospacedDigit().bold())
            if !model.countByLabel.isEmpty {
                Text(
                    model.countByLabel.sorted { $0.key < $1.key }
                        .map { "\($0.key) \($0.value)" }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .combine)
    }

    private var numbersReadout: some View {
        Group {
            if let r = model.latestReading {
                Text(
                    String(
                        format: "Brightness %.0f   Sharpness %.0f   Shake %@",
                        r.brightness,
                        r.sharpness,
                        r.shakePixels.map { String(format: "%.1f px", $0) } ?? "–"
                    ))
            } else {
                Text("No readings yet")
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }

    // MARK: Controls

    private var optionsMenu: some View {
        Menu {
            Toggle("Grayscale preview", isOn: $showGrayscale)
            Toggle("Show numbers", isOn: $showNumbers)
            Button("Sample details") { showDetails = true }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Options")
    }

    /// There is no autofocus. The helper sets focus by hand and it stays put.
    private var focusSlider: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.metering.spot")
            Slider(
                value: Binding(
                    get: { Double(model.lensPosition) }, set: { model.setLensPosition(Float($0)) }),
                in: 0...1
            )
            .accessibilityLabel("Focus")
        }
        .foregroundStyle(.secondary)
    }

    /// The shutter: a red circle to start the sweep, a square to stop it, the way a camera
    /// does it. It stays live while sweeping so the sweep can always be stopped.
    private var captureButton: some View {
        Button {
            if model.recorder.isSweeping {
                model.endSweep()
            } else if details.isComplete {
                details.recordedAt = .now
                model.startSweep(details: details)
            } else {
                showDetails = true
            }
        } label: {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 84, height: 84)
                if model.recorder.isSweeping {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(.red)
                        .frame(width: 68, height: 68)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(!model.isReady && !model.recorder.isSweeping)
        .opacity(model.isReady || model.recorder.isSweeping ? 1 : 0.35)
        .accessibilityLabel(model.recorder.isSweeping ? "Stop sweep" : "Start sweep")
        .accessibilityHint(
            model.isReady || model.recorder.isSweeping ? "" : "Disabled until the image looks good")
    }
}

/// The ring of ticks around the viewfinder. Ticks turn green as the sweep fills up, so how
/// far along it is can be read at a glance from across a bench.
private struct SweepRing: View {
    var fraction: Double
    /// Distance across the ring, measured through the middle of the ticks.
    var diameter: Double
    var tickCount = 48

    var body: some View {
        ZStack {
            ForEach(0..<tickCount, id: \.self) { index in
                Capsule()
                    .fill(isFilled(index) ? Color.green : Color.white)
                    .frame(width: 3, height: 12)
                    .offset(y: -diameter / 2)
                    .rotationEffect(.degrees(Double(index) / Double(tickCount) * 360))
            }
        }
        .animation(.easeOut(duration: 0.2), value: fraction)
        .accessibilityHidden(true)
    }

    private func isFilled(_ index: Int) -> Bool {
        Double(index) < (fraction * Double(tickCount)).rounded()
    }
}

#Preview {
    NavigationStack {
        CaptureView(
            details: .constant(
                SampleDetails(
                    sampleID: "A12",
                    field: 1,
                    moisture: .drained,
                    gramsOfSoil: 10,
                    millilitresScanned: 0.5,
                    recordedAt: .now
                )
            ))
    }
}
