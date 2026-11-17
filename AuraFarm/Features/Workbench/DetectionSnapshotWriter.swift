#if DEBUG
    import CoreImage
    import CoreText
    import CoreVideo
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Saves the frame with its box and id drawn on, each time the slide map counts a new
    /// organism, to Documents/SlideLab/Detections/<run>/ (shown in the Files app). For checking
    /// what the model sees, not sample photos. At most `maxPerRun` a run. Analysis queue only; the
    /// drawing and the write happen on a queue of their own.
    final class DetectionSnapshotWriter {
        static let maxPerRun = 120

        private var directory: URL?
        private(set) var saved = 0
        private let context = CIContext()
        private let queue = DispatchQueue(label: "slidelab.detections", qos: .utility)

        /// A new run: a fresh folder named for its start.
        func begin(stamp: String) {
            saved = 0
            let folder = Self.documents.appending(path: "SlideLab/Detections/\(stamp)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
        }

        static var documents: URL {
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        }

        /// - Parameter boxes: frame pixels from the top left, with the id to write beside each.
        func save(_ buffer: CVPixelBuffer, boxes: [(id: Int, label: String, rect: CGRect)]) {
            guard let directory, saved < Self.maxPerRun else { return }
            let image = CIImage(cvPixelBuffer: buffer)
            guard let picture = context.createCGImage(image, from: image.extent) else { return }
            saved += 1
            let url = directory.appending(path: String(format: "organism-%03d.jpg", saved))
            queue.async { Self.write(picture, boxes: boxes, to: url) }
        }

        private static func write(
            _ base: CGImage, boxes: [(id: Int, label: String, rect: CGRect)], to url: URL
        ) {
            let width = base.width
            let height = base.height
            guard
                let canvas = CGContext(
                    data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            canvas.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
            let green = CGColor(red: 0.2, green: 0.9, blue: 0.3, alpha: 1)
            canvas.setStrokeColor(green)
            canvas.setLineWidth(max(Double(width) / 300, 2))
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, Double(width) / 40, nil)
            for item in boxes {
                // The canvas counts from the bottom left, the boxes from the top left.
                let box = CGRect(
                    x: item.rect.minX, y: Double(height) - item.rect.maxY, width: item.rect.width,
                    height: item.rect.height)
                canvas.stroke(box)
                let caption = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: "\(item.id) \(item.label)",
                        attributes: [
                            NSAttributedString.Key(kCTFontAttributeName as String): font,
                            NSAttributedString.Key(kCTForegroundColorAttributeName as String): green,
                        ]))
                canvas.textPosition = CGPoint(x: box.minX, y: box.maxY + Double(width) / 200)
                CTLineDraw(caption, canvas)
            }
            guard let drawn = canvas.makeImage(),
                let destination = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(
                destination, drawn,
                [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
            CGImageDestinationFinalize(destination)
        }
    }
#endif
