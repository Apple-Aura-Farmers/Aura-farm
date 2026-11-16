#if DEBUG
    import CoreGraphics
    import CoreVideo
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Saves the full luma frame as an 8-bit grayscale PNG named with the movement CSV's seconds
    /// (`frame-013.53.png`), for tuning edge rules from what the camera really saw. Limits: one
    /// automatic frame a second and `maxAutomatic` a session. Analysis queue only; the PNG is
    /// encoded on a queue of its own.
    final class FrameSnapshotWriter {
        static let minGapSeconds = 1.0
        static let maxAutomatic = 80

        private(set) var urls: [URL] = []
        private var directory: URL?
        private var automaticCount = 0
        private var lastAutomaticAt = -Double.infinity
        private let queue = DispatchQueue(label: "slidelab.snapshots", qos: .utility)

        /// A new log: a fresh folder and counts.
        func begin() {
            urls = []
            automaticCount = 0
            lastAutomaticAt = -.infinity
            let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "")
            let folder = FileManager.default.temporaryDirectory.appending(path: "slide-frames-\(stamp)")
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
        }

        static func fileName(forSeconds seconds: Double) -> String {
            String(format: "frame-%06.2f.png", seconds)
        }

        /// Takes the frame; returns the file name written into the CSV row, or nil when a limit
        /// stops it. A manual save ignores the rate and the count.
        /// - Parameter tap: a tap on one of the edge buttons: it ignores the one-a-second limit but
        ///   counts toward the cap.
        func save(
            _ buffer: CVPixelBuffer, csvSeconds: Double, automatic: Bool, tap: Bool = false
        ) -> String? {
            guard let directory else { return nil }
            if automatic || tap {
                guard automaticCount < Self.maxAutomatic else { return nil }
            }
            if automatic {
                guard csvSeconds - lastAutomaticAt >= Self.minGapSeconds else { return nil }
            }
            guard let luma = Self.lumaCopy(of: buffer) else { return nil }
            if automatic || tap { automaticCount += 1 }
            if automatic { lastAutomaticAt = csvSeconds }
            let name = Self.fileName(forSeconds: csvSeconds)
            let url = directory.appending(path: name)
            urls.append(url)
            queue.async { Self.writePNG(luma, to: url) }
            return name
        }

        /// The luma plane without row padding.
        static func lumaCopy(of buffer: CVPixelBuffer) -> (data: Data, width: Int, height: Int)? {
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard CVPixelBufferGetPlaneCount(buffer) > 0,
                let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0)
            else { return nil }
            let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
            let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
            var data = Data(capacity: width * height)
            for row in 0..<height {
                data.append(Data(bytes: base + row * bytesPerRow, count: width))
            }
            return (data, width, height)
        }

        static func writePNG(_ luma: (data: Data, width: Int, height: Int), to url: URL) {
            guard let provider = CGDataProvider(data: luma.data as CFData),
                let image = CGImage(
                    width: luma.width, height: luma.height, bitsPerComponent: 8, bitsPerPixel: 8,
                    bytesPerRow: luma.width, space: CGColorSpaceCreateDeviceGray(),
                    bitmapInfo: CGBitmapInfo(rawValue: 0), provider: provider, decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent),
                let destination = CGImageDestinationCreateWithURL(
                    url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
#endif
