import SwiftUI

/// Debug screen: how fast this phone runs the detector, and what it finds.
///
/// Numbers from the simulator say nothing about a phone — the simulator has no Neural Engine
/// and runs the model on the Mac. Run this on the phone itself.
struct DetectorBenchmarkView: View {
    @State private var hardware = DetectorBenchmark.Hardware.all
    @State private var runs = 30
    @State private var outcome: DetectorBenchmark.Outcome?
    @State private var isRunning = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section("Hardware") {
                Picker("Run on", selection: $hardware) {
                    ForEach(DetectorBenchmark.Hardware.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.navigationLink)
                Stepper("\(runs) runs", value: $runs, in: 10...200, step: 10)
            }

            Section {
                Button {
                    measure()
                } label: {
                    if isRunning {
                        HStack {
                            ProgressView()
                            Text("Running the model…")
                        }
                    } else {
                        Text("Measure")
                    }
                }
                .disabled(isRunning)
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text(
                    """
                    It runs on the first frame of the newest saved sweep, or on a plain square \
                    if nothing has been recorded. Three runs are thrown away first, while the \
                    model is still being moved onto the hardware.
                    """
                )
            }

            if let outcome {
                Section("One frame through the model") {
                    LabeledContent("Median", value: milliseconds(outcome.median))
                    LabeledContent("Fastest", value: milliseconds(outcome.best))
                    LabeledContent("Slowest", value: milliseconds(outcome.worst))
                    LabeledContent(
                        "Frames per second", value: String(format: "%.1f", outcome.framesPerSecond))
                }
                Section("Run") {
                    LabeledContent(
                        "Opening the model", value: milliseconds(outcome.loadMilliseconds))
                    LabeledContent("Picture", value: outcome.imageSize)
                    LabeledContent("Found", value: "\(outcome.detections)")
                }
            }
        }
        .navigationTitle("Detector speed")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func milliseconds(_ value: Double) -> String {
        String(format: "%.1f ms", value)
    }

    private func measure() {
        isRunning = true
        problem = nil
        outcome = nil
        let hardware = hardware
        let runs = runs
        Task {
            do {
                outcome = try await Task.detached(priority: .userInitiated) {
                    try DetectorBenchmark.run(hardware: hardware, runs: runs)
                }.value
            } catch {
                problem = error.localizedDescription
            }
            isRunning = false
        }
    }
}

#Preview {
    NavigationStack { DetectorBenchmarkView() }
}
