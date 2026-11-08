import CoreGraphics
import CoreML
import Foundation
import ImageIO

/// Times the detector on one frame.
///
/// `DetectorBenchmarkView` shows the numbers. Passing `-benchmarkDetector` on the command line
/// prints them instead, which is how they are read off a phone that cannot be tapped from a
/// script.
enum DetectorBenchmark {
    /// What Core ML is allowed to use. The difference between these three is the point of the
    /// measurement: `.all` is what the app would ship with, the other two show what it is
    /// buying.
    enum Hardware: String, CaseIterable, Identifiable {
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

    struct Outcome {
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

    enum Failure: LocalizedError {
        case noImage

        var errorDescription: String? {
            switch self {
            case .noImage: "No picture to run the model on."
            }
        }
    }

    static func run(hardware: Hardware, runs: Int) throws -> Outcome {
        let image = try sampleImage()
        let opened = CFAbsoluteTimeGetCurrent()
        let detector = try OrganismDetector(computeUnits: hardware.computeUnits)
        let loadMilliseconds = (CFAbsoluteTimeGetCurrent() - opened) * 1000

        // The first runs are slow while the model is still being moved onto the hardware.
        // They are not what the app would see.
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

    /// Runs every hardware setting in turn and prints a line each, for reading over a cable.
    static func printEveryHardware(runs: Int = 30) {
        print("BENCH device=\(deviceName) runs=\(runs)")
        for hardware in Hardware.allCases {
            do {
                let outcome = try run(hardware: hardware, runs: runs)
                print(
                    String(
                        format: "BENCH %@ | median %.1f ms | best %.1f | worst %.1f | %.1f fps "
                            + "| open %.0f ms | %@ | found %d",
                        hardware.rawValue, outcome.median, outcome.best, outcome.worst,
                        outcome.framesPerSecond, outcome.loadMilliseconds, outcome.imageSize,
                        outcome.detections
                    ))
            } catch {
                print("BENCH \(hardware.rawValue) | failed: \(error.localizedDescription)")
            }
        }
        print("BENCH done")
    }

    private static var deviceName: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { raw in
            String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
        }
    }

    /// A real frame if one has been recorded, otherwise a plain square. The timings do not
    /// depend on what is in the picture, only on its size.
    static func sampleImage() throws -> CGImage {
        if let frame = SweepLibrary.sweeps().first?.frameURLs.first,
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
