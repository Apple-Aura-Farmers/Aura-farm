#if DEBUG
    import SwiftUI

    /// Point the phone at something and see what the model finds: the default camera, a box and a
    /// label on every detection, the model and the confidence to try. No setup.
    struct ModelTestLabView: View {
        @State private var model = ModelTestLabModel()
        /// V2 with the crop on EVERY time the lab opens (V1 can still be picked for that visit):
        /// V2 calls the bright eyepiece disc an organism without a crop. Not remembered.
        @State private var detectorModel = ModelTestLabDefaults.model
        @State private var cropsToCentre = ModelTestLabDefaults.cropsToCentre
        @AppStorage("modelTest.confidence") private var confidence = 0.3

        var body: some View {
            ScrollView {
                VStack(spacing: 12) {
                    CameraPreview(session: model.session, boxes: model.boxes)
                        .aspectRatio(3 / 4, contentMode: .fit)
                        .overlay(alignment: .topLeading) {
                            Text(model.status)
                                .font(.caption.bold())
                                .padding(6)
                                .background(.black.opacity(0.6), in: Capsule())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    readout
                    controls
                }
                .padding()
            }
            .navigationTitle("Model test")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                model.setModel(detectorModel)
                model.setMinimumConfidence(Float(confidence))
                model.setCropsToCentre(cropsToCentre)
                model.start()
            }
            .onDisappear { model.stop() }
            .onChange(of: detectorModel) { _, picked in model.setModel(picked) }
            .onChange(of: confidence) { _, value in model.setMinimumConfidence(Float(value)) }
            .onChange(of: cropsToCentre) { _, crops in model.setCropsToCentre(crops) }
        }

        private var readout: some View {
            VStack(alignment: .leading, spacing: 4) {
                Text(
                    "\(model.found.count) found · \(model.milliseconds, specifier: "%.1f") ms · \(model.framesPerSecond, specifier: "%.1f") fps"
                )
                .font(.subheadline.monospacedDigit().bold())
                if let load = model.loadMilliseconds {
                    Text("Opened in \(load, specifier: "%.0f") ms").font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.found) { item in
                    Text("\(item.id)  \(item.label)  \(Int((item.confidence * 100).rounded()))%")
                        .font(.footnote.monospaced())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var controls: some View {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Model", selection: $detectorModel) {
                    ForEach(DetectorModel.allCases) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(model.isLoading)
                VStack(alignment: .leading) {
                    Text("Confidence \(confidence, specifier: "%.2f")").font(.caption)
                    Slider(value: $confidence, in: 0.1...0.9, step: 0.05)
                }
                Toggle("Crop to the middle square", isOn: $cropsToCentre)
                Text(
                    "V1's scores are sigmoids of logits and V2's are probabilities, so the same confidence does not mean the same certainty."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    /// What the lab opens on, every time.
    enum ModelTestLabDefaults {
        static let model = DetectorModel.v2
        static let cropsToCentre = true
    }

    #Preview("Opens on V2 with the crop on") {
        NavigationStack { ModelTestLabView() }
    }
#endif
