import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Saves a clean crop (no boxes) of each organism the run's map counts, from the frame that
/// counted it, to Documents/SlideLab/Runs/run-<stamp>-organisms/organism-<id>.jpg. No cap. The
/// crop is cut where `save` is called (the detector queue); scaling and encoding run on a queue of
/// their own.
final class OrganismCropWriter {
    private var stamp = ""
    private let context = CIContext()
    private let queue = DispatchQueue(label: "slidelab.organism-crops", qos: .utility)

    static func fileName(id: Int) -> String { String(format: "organism-%03d.jpg", id) }

    static func folder(stamp: String) -> URL {
        DetectionSnapshotWriter.documents.appending(path: "SlideLab/Runs/run-\(stamp)-organisms")
    }

    /// A new run. The folder is made with its first picture, so a run with no organisms leaves
    /// none.
    func begin(stamp: String) { self.stamp = stamp }

    /// - Parameter items: the map entry's id and its detection box (frame px from the top left).
    func save(_ buffer: CVPixelBuffer, items: [(id: Int, box: CGRect)]) {
        guard !stamp.isEmpty, !items.isEmpty else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let image = CIImage(cvPixelBuffer: buffer)
        let folder = Self.folder(stamp: stamp)
        for item in items {
            let crop = OrganismCrop.rect(
                box: item.box, frame: CGSize(width: width, height: height))
            guard crop.width > 0 else { continue }
            // Core Image counts from the bottom left, the boxes from the top left.
            let flipped = CGRect(
                x: crop.minX, y: Double(height) - crop.maxY, width: crop.width, height: crop.height)
            guard let picture = context.createCGImage(image, from: flipped) else { continue }
            let url = folder.appending(path: Self.fileName(id: item.id))
            queue.async { Self.write(picture, to: url) }
        }
    }

    /// Waits for the pictures still being written.
    func flush() { queue.sync {} }

    private static func write(_ crop: CGImage, to url: URL) {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let side = OrganismCrop.outputSide(for: CGFloat(crop.width))
        guard
            let canvas = CGContext(
                data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return }
        canvas.interpolationQuality = .high
        canvas.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let scaled = canvas.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return }
        CGImageDestinationAddImage(
            destination, scaled, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}
