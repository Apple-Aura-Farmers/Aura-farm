import CoreGraphics
import CoreImage
import CoreML
import CoreVideo

/// The trained detector: an RF-DETR model exported to Core ML.
///
/// It knows five organisms: Arcellinida, Digononta, Euglenoid, Nematode and Volvox. Where
/// those five are concerned it is the most accurate of the weights tried. On 466 frames of
/// a clip that is nothing but Volvox it called all 3652 of its boxes Volvox, where the
/// twenty-six-class YOLO weights it replaced called 873 of their 1807 Vorticella. On 200
/// stills that are all nematodes it says Nematode and the YOLO weights said Paramecium, and
/// it is the only one of the five that finds the nematode in the microscope footage to hand.
///
/// What that costs is breadth. The YOLO weights knew twenty-six organisms, and on a dataset
/// full of ciliates this one was never taught it fires on 14% of images against their 76%.
/// The five it knows it knows well; the rest it does not see at all.
///
/// Vision cannot drive it. A DETR has no non-maximum suppression and no class scores Vision
/// recognises: it answers with a fixed three hundred queries, each a box and a row of
/// logits, so the boxes are decoded here instead.
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

    /// The side of the square the model was trained and exported at.
    static let inputSide = 512

    /// What the model's class slots mean. The head is one wider than the dataset's five
    /// organisms and slot 0 is no-object: a query that lands there is the model saying it
    /// found nothing. Read off the checkpoint's behaviour rather than its metadata, which
    /// carries no names: Nematode dominates a set of nematodes, Volvox dominates a clip of
    /// Volvox, and neither holds under any other reading.
    static let classNames = ["no-object", "Arcellinida", "Digononta", "Euglenoid", "Nematode", "Volvox"]

    /// How sure the model has to be before a query counts as a find.
    ///
    /// NOT CALIBRATED. A DETR scores each class on its own with a sigmoid rather than
    /// sharing one softmax, so its numbers sit lower than the YOLO weights' did and this
    /// cannot be carried over from them. Measured on 600 frames of microscope footage: at
    /// 0.5 it found nothing, at 0.3 nine nematodes, at 0.1 thirty-eight nematodes and seven
    /// euglenoids, with no box covering the frame at any of them. 0.3 is the point where it
    /// is finding things without yet being asked to guess.
    static let leastConfidence: Float = 0.3

    private let model: MLModel
    private let inputName: String
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    /// One square buffer, reused: a frame is squashed into it before every prediction.
    private let square: CVPixelBuffer

    init(computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc")
        else { throw Failure.notInTheBundle }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
        guard let name = model.modelDescription.inputDescriptionsByName.keys.first
        else { throw Failure.notInTheBundle }
        inputName = name

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, Self.inputSide, Self.inputSide, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer)
        guard let buffer else { throw Failure.notInTheBundle }
        square = buffer
    }

    func detections(in image: CGImage) throws -> [Detection] {
        try detections(in: CIImage(cgImage: image))
    }

    /// The live path: a camera frame, with no copy out of it.
    func detections(in buffer: CVPixelBuffer) throws -> [Detection] {
        try detections(in: CIImage(cvPixelBuffer: buffer))
    }

    private func detections(in image: CIImage) throws -> [Detection] {
        // Training squashed whole frames into a square, so feed the model the same way
        // rather than cropping the middle out.
        let side = Double(Self.inputSide)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: side / image.extent.width, y: side / image.extent.height))
        context.render(scaled, to: square)

        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: square)])
        let output = try model.prediction(from: input)
        guard let logits = output.featureValue(for: "logits")?.multiArrayValue,
            let boxes = output.featureValue(for: "boxes")?.multiArrayValue
        else { return [] }
        return Self.decode(logits: logits, boxes: boxes)
    }

    /// Turns the model's three hundred queries into the finds worth keeping.
    ///
    /// Each query carries one box and a logit per class. The best class wins, slot 0 aside,
    /// and its sigmoid is the confidence. The box is the middle and the size, counted from
    /// the top left; everything downstream counts from the bottom left, as Vision did.
    static func decode(logits: MLMultiArray, boxes: MLMultiArray) -> [Detection] {
        let queries = logits.shape[1].intValue
        let classes = logits.shape[2].intValue
        guard classes > 1 else { return [] }

        var found: [Detection] = []
        for query in 0..<queries {
            var best = -Float.greatestFiniteMagnitude
            var bestClass = 1
            for klass in 1..<classes {
                let value = logits[[0, query, klass] as [NSNumber]].floatValue
                if value > best {
                    best = value
                    bestClass = klass
                }
            }
            let confidence = 1 / (1 + exp(-best))
            guard confidence >= leastConfidence else { continue }

            let centreX = boxes[[0, query, 0] as [NSNumber]].doubleValue
            let centreY = boxes[[0, query, 1] as [NSNumber]].doubleValue
            let width = boxes[[0, query, 2] as [NSNumber]].doubleValue
            let height = boxes[[0, query, 3] as [NSNumber]].doubleValue
            let box = CGRect(
                x: centreX - width / 2,
                y: 1 - (centreY + height / 2),
                width: width,
                height: height
            )
            guard !coversWholeFrame(box) else { continue }

            found.append(
                Detection(
                    label: bestClass < classNames.count ? classNames[bestClass] : "class\(bestClass)",
                    confidence: confidence,
                    box: box
                ))
        }
        return found
    }
}
