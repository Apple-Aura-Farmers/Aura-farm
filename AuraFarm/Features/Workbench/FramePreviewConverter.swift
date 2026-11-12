#if DEBUG
    import AVFoundation
    import CoreGraphics

    /// Turns camera-frame pixels into points on the live preview, and back, using the preview
    /// layer's own conversion. The layer knows how the frame is rotated, mirrored and cropped to
    /// fill the view (aspect fill), which a hand-written mapping can only guess.
    ///
    /// A frame rectangle is divided by the frame's size to give a metadata-output rectangle:
    /// `{0, 0}` is the top left and `{1, 1}` the bottom right of the UNROTATED picture, which is
    /// how the frame's top-down pixels are laid out.
    struct FramePreviewConverter {
        let layer: AVCaptureVideoPreviewLayer
        let frameSize: CGSize

        /// nil until there is a layer and a frame to convert for.
        init?(layer: AVCaptureVideoPreviewLayer?, frameSize: CGSize) {
            guard let layer, frameSize.width > 0, frameSize.height > 0 else { return nil }
            self.layer = layer
            self.frameSize = frameSize
        }

        /// The rectangle in the preview's coordinates, for a rectangle in frame pixels.
        func viewRect(of rect: CGRect) -> CGRect {
            layer.layerRectConverted(
                fromMetadataOutputRect: CGRect(
                    x: rect.minX / frameSize.width, y: rect.minY / frameSize.height,
                    width: rect.width / frameSize.width, height: rect.height / frameSize.height))
        }

        func viewPoint(of point: CGPoint) -> CGPoint {
            viewRect(of: CGRect(origin: point, size: .zero)).origin
        }

        /// The frame pixel under a point of the preview.
        func framePoint(fromView point: CGPoint) -> CGPoint {
            let normalised = layer.metadataOutputRectConverted(
                fromLayerRect: CGRect(origin: point, size: .zero))
            return CGPoint(
                x: normalised.origin.x * frameSize.width, y: normalised.origin.y * frameSize.height)
        }

        /// A circle's radius on the preview, in points.
        func viewRadius(of circle: FieldCircle) -> Double {
            let box = viewRect(
                of: CGRect(
                    x: circle.centre.x - circle.radius, y: circle.centre.y - circle.radius,
                    width: circle.radius * 2, height: circle.radius * 2))
            return Double(min(box.width, box.height)) / 2
        }
    }
#endif
