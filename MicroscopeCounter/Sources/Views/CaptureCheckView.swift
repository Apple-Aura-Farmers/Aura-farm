import AVFoundation
import SwiftUI

/// Camera preview with a live quality check. Recording is only allowed when the image is good.
struct CaptureCheckView: View {
    @State private var model = CameraQualityModel()
    /// Tap the banner to show the live numbers. Used to calibrate thresholds.
    @State private var showNumbers = false
    /// Preview only: clips are always recorded in colour, grayscale comes later in the pipeline.
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
        // A saved clip means this field is done: count up and go back to the menu,
        // where the clip can be played back.
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
            StatusBanner(systemImage: "exclamationmark.triangle", title: "Camera problem", message: error, tint: .red)
        } else if model.recorder.isRecording {
            StatusBanner(systemImage: "record.circle", title: "Recording", message: "Keep still until you press Stop.", tint: .red)
        } else if let error = model.recorder.errorMessage {
            StatusBanner(systemImage: "exclamationmark.triangle", title: "Saving problem", message: error, tint: .red)
        } else if let issue = model.topIssue {
            StatusBanner(systemImage: issue.systemImage, title: issue.title, message: issue.advice, tint: .orange)
        } else if model.isReady {
            StatusBanner(systemImage: "checkmark.circle.fill", title: "Ready to record", message: "The image looks good.", tint: .green)
        } else {
            StatusBanner(systemImage: "hourglass", title: "Checking the image", message: "Hold still for a moment.", tint: .gray)
        }
    }

    private var numbersReadout: some View {
        Group {
            if let r = model.latestReading {
                Text(String(
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
                value: Binding(get: { Double(model.lensPosition) }, set: { model.setLensPosition(Float($0)) }),
                in: 0...1
            )
            .accessibilityLabel("Focus")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.6), in: Capsule())
        .foregroundStyle(.white)
    }

    // MARK: Record button

    private var recordButton: some View {
        Button {
            if model.recorder.isRecording {
                model.recorder.stop()
            } else if details.isComplete {
                details.recordedAt = .now
                model.recorder.start(metadata: details)
            } else {
                showDetails = true
            }
        } label: {
            Label(
                model.recorder.isRecording ? "Stop" : "Record",
                systemImage: model.recorder.isRecording ? "stop.circle" : "record.circle"
            )
            .font(.title2.bold())
            .frame(maxWidth: .infinity)
            .padding()
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!model.isReady && !model.recorder.isRecording)
        .accessibilityHint(model.isReady || model.recorder.isRecording ? "" : "Disabled until the image looks good")
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
    CaptureCheckView(details: .constant(
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
