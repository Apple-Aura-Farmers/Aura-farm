import CoreGraphics
import CoreImage
import CoreML
import CoreVideo
import QuartzCore

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

    /// Where one detection's time went, in milliseconds: cropping and rendering into the square,
    /// the model alone, and turning its answer into detections.
    struct Timing: Equatable {
        var preMilliseconds = 0.0
        var inferMilliseconds = 0.0
        var decodeMilliseconds = 0.0
        /// The scores' and boxes' shape, strides and type; set on the first decode only.
        var outputLayout: String?
        var totalMilliseconds: Double { preMilliseconds + inferMilliseconds + decodeMilliseconds }
    }

    enum Failure: LocalizedError {
        case notInTheBundle

        var errorDescription: String? {
            switch self {
            case .notInTheBundle: "The detector model is not in the app."
            }
        }
    }

    /// Xcode compiles `SoilDetectorV3.mlpackage` into `SoilDetectorV3.mlmodelc` in the bundle.
    static let modelName = DetectorModel.v3.resourceName

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
    /// The hardware it was opened for.
    let computeUnits: MLComputeUnits
    var modelName: String { kind.resourceName }

    private let network: MLModel
    private let inputName: String
    private let context = CIContext(options: [.useSoftwareRenderer: false])
    /// One square buffer, reused: a frame is squashed into it before every prediction.
    private let square: CVPixelBuffer
    /// Whether the output layout has been reported yet; a class so the struct can stay immutable.
    private final class Flag { var done = false }
    private let layoutReported = Flag()

    /// With no arguments this is V3, the only model the app ships.
    init(model kind: DetectorModel = .v3, computeUnits: MLComputeUnits = .all) throws {
        guard let url = Bundle.main.url(forResource: kind.resourceName, withExtension: "mlmodelc")
        else { throw Failure.notInTheBundle }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let network = try MLModel(contentsOf: url, configuration: configuration)
        guard let name = network.modelDescription.inputDescriptionsByName.keys.first
        else { throw Failure.notInTheBundle }
        self.kind = kind
        self.computeUnits = computeUnits
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
    /// The class names of `kind`, read from the model's metadata ("classes", comma separated)
    /// and checked against the scores' width.
    static func names(for kind: DetectorModel, in network: MLModel) -> [String] {
        let builtIn = kind.builtInClassNames
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
        return builtIn
    }

    func detections(in image: CGImage, crop: CGRect? = nil) throws -> [Detection] {
        try run(CIImage(cgImage: image), crop: crop).found
    }

    /// The live path: a camera frame, with no copy out of it.
    func detections(in buffer: CVPixelBuffer, crop: CGRect? = nil) throws -> [Detection] {
        try run(CIImage(cvPixelBuffer: buffer), crop: crop).found
    }

    /// The live path with the time split.
    func timedDetections(
        in buffer: CVPixelBuffer, crop: CGRect? = nil
    ) throws -> (found: [Detection], timing: Timing) {
        try run(CIImage(cvPixelBuffer: buffer), crop: crop)
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

    private func run(_ whole: CIImage, crop: CGRect?) throws -> (found: [Detection], timing: Timing) {
        var timing = Timing()
        var mark = CACurrentMediaTime()
        func lap() -> Double {
            let now = CACurrentMediaTime()
            defer { mark = now }
            return (now - mark) * 1000
        }
        let image = crop.map { Self.cropped(whole, to: $0) } ?? whole
        // Training squashed whole frames into a square, so feed the model the same way
        // rather than cropping the middle out.
        let side = Double(Self.inputSide)
        let scaled = image.transformed(
            by: CGAffineTransform(
                scaleX: side / image.extent.width, y: side / image.extent.height))
        context.render(scaled, to: square)
        timing.preMilliseconds = lap()

        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: square)])
        let output = try network.prediction(from: input)
        timing.inferMilliseconds = lap()
        guard let scores = output.featureValue(for: kind.scoresOutput)?.multiArrayValue,
            let boxes = output.featureValue(for: "boxes")?.multiArrayValue
        else { return ([], timing) }
        if !layoutReported.done {
            layoutReported.done = true
            let text = "scores \(Self.describe(scores)); boxes \(Self.describe(boxes))"
            timing.outputLayout = text
            print("DETECTOR \(kind.resourceName) output layout: \(text)")
        }
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
        timing.decodeMilliseconds = lap()
        return (found, timing)
    }

    /// "shape [1,300,24] strides [9600,32,1] float16", for the log.
    static func describe(_ array: MLMultiArray) -> String {
        let shape = array.shape.map(\.stringValue).joined(separator: ",")
        let strides = array.strides.map(\.stringValue).joined(separator: ",")
        return "shape [\(shape)] strides [\(strides)] type \(array.dataType.rawValue)"
    }

    /// The logit path: scores that need a sigmoid, under the caller's class names. No model
    /// the app ships takes it, V3's graph ending in a sigmoid, but the decode still has to do
    /// it right and the tests go through here.
    static func decode(
        logits: MLMultiArray, boxes: MLMultiArray, classNames: [String],
        minimumConfidence: Float = leastConfidence
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
        if let found = decodeByRows(
            scores: scores, boxes: boxes, classNames: classNames,
            scoresAreProbabilities: scoresAreProbabilities, minimumConfidence: minimumConfidence)
        {
            return found
        }
        return decodeGeneral(
            scores: scores, boxes: boxes, classNames: classNames,
            scoresAreProbabilities: scoresAreProbabilities, minimumConfidence: minimumConfidence)
    }

    /// One element of `raw` as a Double: Float32 and Double straight, Float16 widened exactly.
    @inline(__always)
    private static func element(_ raw: UnsafeRawBufferPointer, _ type: MLMultiArrayDataType, _ n: Int)
        -> Double
    {
        switch type {
        case .float32: return Double(raw.loadUnaligned(fromByteOffset: n * 4, as: Float.self))
        case .double: return raw.loadUnaligned(fromByteOffset: n * 8, as: Double.self)
        default: return Double(halfToFloat(raw.loadUnaligned(fromByteOffset: n * 2, as: UInt16.self)))
        }
    }

    /// The fast path: both arrays [1, queries, width] with an innermost stride of 1, whatever the
    /// row and batch strides. Each row is read in place, a box only for a query that passes.
    /// nil when the layout is anything else, so `decodeGeneral` takes it.
    private static func decodeByRows(
        scores: MLMultiArray, boxes: MLMultiArray, classNames: [String],
        scoresAreProbabilities: Bool, minimumConfidence: Float
    ) -> [Detection]? {
        let scoreShape = scores.shape.map(\.intValue)
        let boxShape = boxes.shape.map(\.intValue)
        let scoreStrides = scores.strides.map(\.intValue)
        let boxStrides = boxes.strides.map(\.intValue)
        let supported: Set<MLMultiArrayDataType> = [.float32, .float16, .double]
        guard scoreShape.count == 3, boxShape.count == 3, scoreShape[0] == 1, boxShape[0] == 1,
            scoreShape[2] > 1, boxShape[1] >= scoreShape[1], boxShape[2] >= 4,
            scoreStrides[2] == 1, boxStrides[2] == 1,
            supported.contains(scores.dataType), supported.contains(boxes.dataType)
        else { return nil }
        let queries = scoreShape[1]
        let classes = scoreShape[2]
        let scoreType = scores.dataType
        let boxType = boxes.dataType
        var found: [Detection] = []
        scores.withUnsafeBytes { scoreRaw in
            boxes.withUnsafeBytes { boxRaw in
                for query in 0..<queries {
                    let row = query * scoreStrides[1]
                    var best = -Float.greatestFiniteMagnitude
                    var bestClass = 1
                    for klass in 1..<classes {
                        let value = Float(element(scoreRaw, scoreType, row + klass))
                        if value > best {
                            best = value
                            bestClass = klass
                        }
                    }
                    let confidence = scoresAreProbabilities ? best : 1 / (1 + exp(-best))
                    guard confidence >= minimumConfidence else { continue }

                    let at = query * boxStrides[1]
                    let centreX = element(boxRaw, boxType, at)
                    let centreY = element(boxRaw, boxType, at + 1)
                    let width = element(boxRaw, boxType, at + 2)
                    let height = element(boxRaw, boxType, at + 3)
                    let box = CGRect(
                        x: centreX - width / 2, y: 1 - (centreY + height / 2), width: width,
                        height: height)
                    guard !coversWholeFrame(box) else { continue }
                    found.append(
                        Detection(
                            label: bestClass < classNames.count
                                ? classNames[bestClass] : "class\(bestClass)",
                            confidence: confidence, box: box))
                }
            }
        }
        return found
    }

    /// The general path for any layout: every value copied out through its strides first.
    static func decodeGeneral(
        scores: MLMultiArray, boxes: MLMultiArray, classNames: [String],
        scoresAreProbabilities: Bool, minimumConfidence: Float = leastConfidence
    ) -> [Detection] {
        let queries = scores.shape[1].intValue
        let classes = scores.shape[2].intValue
        guard classes > 1 else { return [] }
        let scoreValues = values(of: scores)
        let boxValues = values(of: boxes)

        var found: [Detection] = []
        for query in 0..<queries {
            var best = -Float.greatestFiniteMagnitude
            var bestClass = 1
            for klass in 1..<classes {
                let value = Float(scoreValues[query * classes + klass])
                if value > best {
                    best = value
                    bestClass = klass
                }
            }
            let confidence = scoresAreProbabilities ? best : 1 / (1 + exp(-best))
            guard confidence >= minimumConfidence else { continue }

            let centreX = boxValues[query * 4]
            let centreY = boxValues[query * 4 + 1]
            let width = boxValues[query * 4 + 2]
            let height = boxValues[query * 4 + 3]
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

    /// Every element of `array` in row-major order, read straight from its memory with its
    /// strides and data type, as doubles. Float16 and Float32 widen exactly, so what the old
    /// `NSNumber` subscripts gave is what this gives. Reading 7000 elements through subscripts
    /// built an `NSNumber` for each.
    static func values(of array: MLMultiArray) -> [Double] {
        let shape = array.shape.map(\.intValue)
        let strides = array.strides.map(\.intValue)
        let count = shape.reduce(1, *)
        var result = [Double](repeating: 0, count: count)
        guard count > 0, !shape.isEmpty else { return result }
        let type = array.dataType
        var running = 1
        var contiguous = true
        for dimension in stride(from: shape.count - 1, through: 0, by: -1) {
            if strides[dimension] != running { contiguous = false }
            running *= shape[dimension]
        }
        if contiguous {
            // The usual case: one run of elements in order.
            array.withUnsafeBytes { raw in
                switch type {
                case .float32:
                    let source = raw.bindMemory(to: Float.self)
                    for n in 0..<count { result[n] = Double(source[n]) }
                case .double:
                    let source = raw.bindMemory(to: Double.self)
                    for n in 0..<count { result[n] = source[n] }
                case .float16:
                    let source = raw.bindMemory(to: UInt16.self)
                    for n in 0..<count { result[n] = Double(halfToFloat(source[n])) }
                default: break
                }
            }
            return result
        }
        array.withUnsafeBytes { raw in
            func element(_ offset: Int) -> Double {
                switch type {
                case .float32: return Double(raw.loadUnaligned(fromByteOffset: offset * 4, as: Float.self))
                case .double: return raw.loadUnaligned(fromByteOffset: offset * 8, as: Double.self)
                case .float16:
                    return Double(
                        halfToFloat(raw.loadUnaligned(fromByteOffset: offset * 2, as: UInt16.self)))
                default: return 0
                }
            }
            var index = [Int](repeating: 0, count: shape.count)
            for n in 0..<count {
                var offset = 0
                for dimension in 0..<shape.count { offset += index[dimension] * strides[dimension] }
                result[n] = element(offset)
                var dimension = shape.count - 1
                while dimension >= 0 {
                    index[dimension] += 1
                    if index[dimension] < shape[dimension] { break }
                    index[dimension] = 0
                    dimension -= 1
                }
            }
        }
        return result
    }

    /// An IEEE half as a float, exactly. Written out because `Float16` is missing on Intel
    /// simulators.
    static func halfToFloat(_ bits: UInt16) -> Float {
        let sign: UInt32 = UInt32(bits & 0x8000) << 16
        let exponent = UInt32((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x3FF)
        if exponent == 0 {
            if mantissa == 0 { return Float(bitPattern: sign) }
            // Subnormal: mantissa * 2^-24.
            let magnitude = Float(mantissa) * Float(sign: .plus, exponent: -24, significand: 1)
            return sign == 0 ? magnitude : -magnitude
        }
        if exponent == 0x1F { return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) }
        return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
    }
}
