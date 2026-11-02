import CoreGraphics
import CoreML
import ImageIO
import SwiftUI

/// Debug screen: how fast this phone runs the detector, and what it finds.
///
/// Numbers from the simulator say nothing about a phone — the simulator has no Neural Engine
/// and runs the model on the Mac. Run this on the phone itself.
struct DetectorBenchView: View {
    /// What Core ML is allowed to use. The difference between these three is the point of the
    /// screen: `.all` is what the app would ship with, the other two show what it is buying.
    private enum Hardware: String, CaseIterable, Identifiable {
        case all = "Neural Engine, GPU, CPU"
        case gpu = "GPU and CPU"
        case cpu = "CPU only"

        var id: Self { self }

        var computeUnits: MLComputeUnits {
            switch self {
            case .all: .all
            case .gpu: .cpuAndGPU
            case .cpu: .cpuOnly
            }
        }
    }

    private struct Outcome {
        /// Opening the model: reading it, and handing it to the hardware.
        var loadMilliseconds: Double
        /// One entry per timed run, sorted.
        var milliseconds: [Double]
        var detections: Int
        var imageSize: String

        var median: Double { milliseconds[milliseconds.count / 2] }
        var best: Double { milliseconds[0] }
        var worst: Double { milliseconds[milliseconds.count - 1] }
        var framesPerSecond: Double { median > 0 ? 1000 / median : 0 }
    }

    private enum Failure: LocalizedError {
        case noImage

        var errorDescription: String? {
            switch self {
            case .noImage: "No picture to run the model on."
            }
        }
    }

    @State private var hardware = Hardware.all
    @State private var runs = 30
    @State private var outcome: Outcome?
    @State private var isRunning = false
    @State private var problem: String?

    var body: some View {
        Form {
            Section("Hardware") {
                Picker("Run on", selection: $hardware) {
                    ForEach(Hardware.allCases) { Text($0.rawValue).tag($0) }
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
                    LabeledContent("Opening the model", value: milliseconds(outcome.loadMilliseconds))
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
                    try Self.benchmark(hardware: hardware, runs: runs)
                }.value
            } catch {
                problem = error.localizedDescription
            }
            isRunning = false
        }
    }

    private static func benchmark(hardware: Hardware, runs: Int) throws -> Outcome {
        let image = try sampleImage()
        let opened = CFAbsoluteTimeGetCurrent()
        let detector = try Detector(computeUnits: hardware.computeUnits)
        let loadMilliseconds = (CFAbsoluteTimeGetCurrent() - opened) * 1000

        for _ in 0..<3 { _ = try detector.detections(in: image) }

        var milliseconds: [Double] = []
        var detections = 0
        for _ in 0..<runs {
            let started = CFAbsoluteTimeGetCurrent()
            detections = try detector.detections(in: image).count
            milliseconds.append((CFAbsoluteTimeGetCurrent() - started) * 1000)
        }
        return Outcome(
            loadMilliseconds: loadMilliseconds,
            milliseconds: milliseconds.sorted(),
            detections: detections,
            imageSize: "\(image.width) x \(image.height)"
        )
    }

    /// A real frame if one has been recorded, otherwise a plain square. The timings do not
    /// depend on what is in the picture, only on its size.
    private static func sampleImage() throws -> CGImage {
        if let frame = FrameSetLibrary.frameSets().first?.frameURLs.first,
            let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        {
            return image
        }
        let side = 640
        guard
            let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { throw Failure.noImage }
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context.makeImage() else { throw Failure.noImage }
        return image
    }
}

#Preview {
    NavigationStack { DetectorBenchView() }
}
