import AVFoundation
import SwiftUI

/// Camera preview with a live quality check, and the sweep that keeps still frames.
/// Frames are only kept when the image is good.
struct CaptureCheckView: View {
    @State private var model = CameraQualityModel()
    /// Tap the banner to show the live numbers. Used to calibrate thresholds.
    @State private var showNumbers = false
    /// Preview only: frames are always saved in colour, grayscale comes later in the pipeline.
    @State private var showGrayscale = false
    @State private var showDetails = false
    @Environment(\.dismiss) private var dismiss
    /// Owned by the setup screen, so the field number it counts up survives leaving the camera.
    @Binding var details: RecordingMetadata

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.session)
                .grayscale(showGrayscale ? 1 : 0)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    banner
                        .onTapGesture { showNumbers.toggle() }
                    optionsMenu
                }
                if showNumbers { numbersReadout }
                sampleLine
                Spacer()
                if model.recorder.isSweeping { sweepPrompt }
                focusSlider
                recordButton
            }
            .padding()
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

    // MARK: Banner

    @ViewBuilder
    private var banner: some View {
        if model.authorization == .denied || model.authorization == .restricted {
            StatusBanner(
                systemImage: "camera.fill",
                title: "Camera is off",
                message: "Allow camera access in Settings to use this app.",
                tint: .red
            )
        } else if let error = model.cameraError {
            StatusBanner(
                systemImage: "exclamationmark.triangle", title: "Camera problem", message: error, tint: .red)
        } else if let issue = model.topIssue, FrameSweep.blocksCapture(issue),
            model.recorder.isSweeping
        {
            // While a sweep is paused the helper needs to see what to fix, not a count.
            StatusBanner(
                systemImage: issue.systemImage, title: issue.title, message: issue.advice, tint: .orange)
        } else if model.recorder.isSweeping {
            StatusBanner(
                systemImage: "square.stack.3d.up",
                title: "Keeping frames",
                message: "\(model.recorder.keptCount) saved. Frames save on their own.",
                tint: .red
            )
        } else if let error = model.recorder.errorMessage {
            StatusBanner(
                systemImage: "exclamationmark.triangle", title: "Saving problem", message: error, tint: .red)
        } else if let issue = model.topIssue {
            StatusBanner(
                systemImage: issue.systemImage, title: issue.title, message: issue.advice, tint: .orange)
        } else if model.isReady {
            StatusBanner(
                systemImage: "checkmark.circle.fill", title: "Ready to start",
                message: "The image looks good.", tint: .green)
        } else {
            StatusBanner(
                systemImage: "hourglass", title: "Checking the image", message: "Hold still for a moment.",
                tint: .gray)
        }
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
        .padding(8)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
        .foregroundStyle(.white)
    }

    /// The one thing to do right now, large enough to read at arm's length on a microscope.
    private var sweepPrompt: some View {
        let prompt = model.sweepPrompt
        return HStack(spacing: 14) {
            Image(systemName: prompt.systemImage)
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 6) {
                Text(prompt.title).font(.title2.bold())
                Text(prompt.advice).font(.subheadline)
                sweepProgress
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    /// A dot for each frame in the row being walked, and a bar for the whole sweep, so the
    /// helper can see how much further to go without counting anything.
    private var sweepProgress: some View {
        let progress = model.sweepProgress
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(0..<progress.framesPerRow, id: \.self) { position in
                    Circle()
                        .fill(position < progress.keptInRow ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
                Text("row \(progress.row) of \(progress.rowCount)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
            }
            ProgressView(value: progress.fraction)
                .tint(.white)
        }
        .accessibilityLabel(
            "\(progress.kept) of \(progress.total) frames saved, row \(progress.row) of \(progress.rowCount)"
        )
    }

    @ViewBuilder
    private var sampleLine: some View {
        if details.isComplete {
            Button {
                showDetails = true
            } label: {
                Text("\(details.sampleID) · field \(details.field) · \(details.moisture.label)")
                    .font(.caption)
                    .padding(8)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
    }

    // MARK: Options

    private var optionsMenu: some View {
        Menu {
            Toggle("Grayscale preview", isOn: $showGrayscale)
            Toggle("Show numbers", isOn: $showNumbers)
            Button("Sample details") { showDetails = true }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(6)
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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
    }

    // MARK: Start button

    private var recordButton: some View {
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
            Label(
                model.recorder.isSweeping ? "Stop" : "Start sweep",
                systemImage: model.recorder.isSweeping ? "stop.circle" : "square.stack.3d.up"
            )
            .font(.title2.bold())
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!model.isReady && !model.recorder.isSweeping)
        .accessibilityHint(
            model.isReady || model.recorder.isSweeping ? "" : "Disabled until the image looks good")
    }
}

private struct StatusBanner: View {
    let systemImage: String
    let title: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(message).font(.subheadline)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    CaptureCheckView(
        details: .constant(
            RecordingMetadata(
                sampleID: "A12",
                field: 1,
                moisture: .drained,
                gramsOfSoil: 10,
                millilitresScanned: 0.5,
                recordedAt: .now
            )
        ))
}
