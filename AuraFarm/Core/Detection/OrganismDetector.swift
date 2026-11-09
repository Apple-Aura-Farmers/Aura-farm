import CoreGraphics
import CoreML
import Vision

/// The trained detector: a YOLO26n model exported to Core ML with non-maximum suppression
/// built into the model, so Vision hands back finished boxes rather than raw tensors.
///
/// The model knows twenty-six classes, named as it names them: Amoeba, Nematode, Ceratium,
/// Coleps, Collodictyon, Colsterium, Cylindrocystis, Didinium, Dinobryon, Frontonia,
/// Lepocinclis, Micrasterias, Paramecium, Peridinium, Phacus, Pinnularia, Pleurotaenium,
/// Pyrocystis, Volvox, Euglena, Stentor, Vorticella, Arcellinida, Digononta, Monogononta
/// and Hypotrichida.
///
/// Four trained weights were held against each other on 200 nematode stills, 200 stills of
/// ciliates and 600 frames of real microscope footage. This one, the only one that knows all
/// twenty-six, found the most on the footage of any that kept its boxes sensible: 61 boxes
/// over 600 frames with none covering more than 80% of the frame. The five-class weights it
/// replaced found 48 on the same frames, and the nineteen-class one found 153 but 39 of
/// those covered the frame, which is the model shrugging rather than finding anything.
///
/// It does not settle nematodes. On 200 stills that are all nematodes it labelled 7 of them
/// Nematode and 52 Paramecium, and over the 600 frames it never said Nematode once, though
/// one is plainly in them. Counting nematodes needs weights that can find them.
///
/// `computeUnits` is open so the benchmark can hold the Neural Engine, the GPU and the CPU
/// against each other. Anywhere else, leave it at `.all` and let Core ML choose.
struct OrganismDetector {
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

    /// A box covering more of the frame than this is thrown away before anything counts it.
    ///
    /// A model with nothing to say answers with the whole picture. The nineteen-class
    /// weights did it on 39 of their 107 nematode boxes over 600 frames of real footage, and
    /// the five-class ones on 113 of their 160 boxes over 200 nematode stills, which are
    /// images of an organism neither of them knows. The weights in use here do it on 42 of
    /// 118 boxes over those same stills and on none at all over the footage, so the guard
    /// still has work to do on a slide the model was not trained for.
    ///
    /// Not calibrated against a stage. At a low enough magnification one large organism
    /// could fill this much of the field honestly, and it would be dropped.
    static let largestBoxShare = 0.8

    /// Whether a box is the model answering about the whole picture rather than finding
    /// something in it. The box is a share of the frame, so its area is one already.
    static func coversWholeFrame(_ box: CGRect) -> Bool {
        box.width * box.height > largestBoxShare
    }

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
        return observations.filter { !Self.coversWholeFrame($0.boundingBox) }.map { observation in
            Detection(
                label: observation.labels.first?.identifier ?? "?",
                confidence: observation.labels.first?.confidence ?? 0,
                box: observation.boundingBox
            )
        }
    }
}
