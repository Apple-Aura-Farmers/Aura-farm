import CoreGraphics
import CoreML
import Vision

/// The trained detector: a YOLO26n model exported to Core ML with non-maximum suppression
/// built into the model, so Vision hands back finished boxes rather than raw tensors.
///
/// The model knows five classes, named as it names them: euglena, paramecium, stentor,
/// volvox and vorticella.
///
/// Two other trained weights were tried against the same footage. The nineteen-class one
/// answered "Nematode" with a box covering the whole frame on 74 of its 134 hits, which is
/// the model shrugging rather than finding anything, so this one is in instead.
///
/// `computeUnits` is open so the benchmark can hold the Neural Engine, the GPU and the CPU
/// against each other. Anywhere else, leave it at `.all` and let Core ML choose.
struct Detector {
    /// One thing the model found.
    struct Detection: Identifiable {
        let id = UUID()
        var label: String
        var confidence: Float
        /// Vision's coordinates: a share of the image, with the origin at the bottom left.
        var box: CGRect
    }

    enum Failure: LocalizedError {
        case notInTheBundle

        var errorDescription: String? {
            switch self {
            case .notInTheBundle: "The detector model is not in the app."
            }
        }
    }

    /// Xcode compiles `SoilDetector.mlpackage` into `SoilDetector.mlmodelc` in the bundle.
    static let modelName = "SoilDetector"

    private let visionModel: VNCoreMLModel

    init(computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc")
        else { throw Failure.notInTheBundle }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        visionModel = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: configuration))
    }

    func detections(in image: CGImage) throws -> [Detection] {
        try detections(from: VNImageRequestHandler(cgImage: image))
    }

    /// The live path: a camera frame, with no copy out of it.
    func detections(in buffer: CVPixelBuffer) throws -> [Detection] {
        try detections(from: VNImageRequestHandler(cvPixelBuffer: buffer))
    }

    private func detections(from handler: VNImageRequestHandler) throws -> [Detection] {
        let request = VNCoreMLRequest(model: visionModel)
        // Training squashed whole frames into a square, so feed the model the same way rather
        // than cropping the middle out.
        request.imageCropAndScaleOption = .scaleFill
        try handler.perform([request])
        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        return observations.map { observation in
            Detection(
                label: observation.labels.first?.identifier ?? "?",
                confidence: observation.labels.first?.confidence ?? 0,
                box: observation.boundingBox
            )
        }
    }
}
