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

    /// The confidence a query needs to count as a find. Defaults to `leastConfidence`, so only a
    /// caller that sets it sees anything different.
    var minimumConfidence = OrganismDetector.leastConfidence

    /// Which model this is, its class names (slot 0 the background or no-object) and its name.
    let kind: DetectorModel
    let classNames: [String]
    var modelName: String { kind.resourceName }

    private let network: MLModel
    private let inputName: String
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    /// One square buffer, reused: a frame is squashed into it before every prediction.
    private let square: CVPixelBuffer

    /// With no arguments this is V1 with today's behaviour.
    init(model kind: DetectorModel = .v1, computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.main.url(forResource: kind.resourceName, withExtension: "mlmodelc")
        else { throw Failure.notInTheBundle }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let network = try MLModel(contentsOf: url, configuration: configuration)
        guard let name = network.modelDescription.inputDescriptionsByName.keys.first
        else { throw Failure.notInTheBundle }
        self.kind = kind
        self.network = network
        inputName = name
        classNames = Self.names(for: kind, in: network)

        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(
            nil, Self.inputSide, Self.inputSide, kCVPixelFormatType_32BGRA,
            [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary, &buffer)
        guard let buffer else { throw Failure.notInTheBundle }
        square = buffer
    }

    /// - Parameter crop: a square in frame pixels, origin at the top left; only it is squashed to
    ///   the model's input, and the boxes come back as shares of the WHOLE frame. nil feeds the
    ///   whole frame, as the model was trained.
    /// The class names of `kind`: V1's are fixed; V2's are read from the model's metadata
    /// ("classes", comma separated) and checked against the scores' width.
    static func names(for kind: DetectorModel, in network: MLModel) -> [String] {
        guard kind == .v2 else { return Self.classNames }
        let width = network.modelDescription.outputDescriptionsByName[kind.scoresOutput]?
            .multiArrayConstraint?.shape.last?.intValue
        let metadata = network.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
        let fromModel = metadata?["classes"]?.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let fromModel, fromModel.count == width { return fromModel }
        #if DEBUG
            print(
                "DETECTOR \(kind.resourceName): class list missing or the wrong length "
                    + "(\(fromModel?.count ?? 0) names, scores \(width ?? 0) wide); using the built-in list"
            )
        #endif
        return DetectorModel.v2ClassNames
    }

    func detections(in image: CGImage, crop: CGRect? = nil) throws -> [Detection] {
        try detections(in: CIImage(cgImage: image), crop: crop)
    }

    /// The live path: a camera frame, with no copy out of it.
    func detections(in buffer: CVPixelBuffer, crop: CGRect? = nil) throws -> [Detection] {
        try detections(in: CIImage(cvPixelBuffer: buffer), crop: crop)
    }

    /// A box that is a share of `crop` (Vision's axes: origin bottom left) as a share of the
    /// whole frame. `crop` is in frame pixels with the origin at the top left.
    static func boxInFrame(_ box: CGRect, crop: CGRect, frameSize: CGSize) -> CGRect {
        let width = Double(frameSize.width)
        let height = Double(frameSize.height)
        let originX = crop.minX / width
        let originY = (height - crop.maxY) / height
        let shareWidth = crop.width / width
        let shareHeight = crop.height / height
        return CGRect(
            x: originX + box.minX * shareWidth, y: originY + box.minY * shareHeight,
            width: box.width * shareWidth, height: box.height * shareHeight)
    }

    /// The part of `image` inside `crop` (frame pixels, origin top left), moved to the origin.
    /// Core Image counts from the bottom left, so the rectangle is flipped here; proved on a
    /// marked picture in `V2DetectorTests`.
    static func cropped(_ image: CIImage, to crop: CGRect) -> CIImage {
        let rect = CGRect(
            x: crop.minX, y: image.extent.height - crop.maxY, width: crop.width,
            height: crop.height)
        return image.cropped(to: rect).transformed(
            by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY))
    }

    private func detections(in whole: CIImage, crop: CGRect?) throws -> [Detection] {
        let image = crop.map { Self.cropped(whole, to: $0) } ?? whole
        // Training squashed whole frames into a square, so feed the model the same way
        // rather than cropping the middle out.
        let side = Double(Self.inputSide)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: side / image.extent.width, y: side / image.extent.height))
        context.render(scaled, to: square)

        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: square)])
        let output = try network.prediction(from: input)
        guard let scores = output.featureValue(for: kind.scoresOutput)?.multiArrayValue,
            let boxes = output.featureValue(for: "boxes")?.multiArrayValue
        else { return [] }
        var found = Self.decode(
            scores: scores, boxes: boxes, classNames: classNames,
            scoresAreProbabilities: kind.scoresAreProbabilities,
            minimumConfidence: minimumConfidence)
        if let crop {
            let frame = whole.extent.size
            for index in found.indices {
                found[index].box = Self.boxInFrame(found[index].box, crop: crop, frameSize: frame)
            }
        }
        return found
    }

    /// V1's path: logits and V1's class names. What the existing callers and tests use.
    static func decode(
        logits: MLMultiArray, boxes: MLMultiArray, minimumConfidence: Float = leastConfidence
    ) -> [Detection] {
        decode(
            scores: logits, boxes: boxes, classNames: classNames, scoresAreProbabilities: false,
            minimumConfidence: minimumConfidence)
    }

    /// Turns the model's three hundred queries into the finds worth keeping.
    ///
    /// Each query carries one box and a score per class. The best class wins, slot 0 aside. A
    /// probability is the confidence as it is; a logit goes through a sigmoid first. The box is
    /// the middle and the size, counted from the top left; everything downstream counts from the
    /// bottom left, as Vision did.
    static func decode(
        scores: MLMultiArray, boxes: MLMultiArray, classNames: [String],
        scoresAreProbabilities: Bool, minimumConfidence: Float = leastConfidence
    ) -> [Detection] {
        let queries = scores.shape[1].intValue
        let classes = scores.shape[2].intValue
        guard classes > 1 else { return [] }

        var found: [Detection] = []
        for query in 0..<queries {
            var best = -Float.greatestFiniteMagnitude
            var bestClass = 1
            for klass in 1..<classes {
                let value = scores[[0, query, klass] as [NSNumber]].floatValue
                if value > best {
                    best = value
                    bestClass = klass
                }
            }
            let confidence = scoresAreProbabilities ? best : 1 / (1 + exp(-best))
            guard confidence >= minimumConfidence else { continue }

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
