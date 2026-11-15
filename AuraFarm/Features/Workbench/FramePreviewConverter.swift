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
    ///
    /// `display` is the transform the lab applies to the picture to centre the field (see
    /// `fitTransform`): the layer's own coordinates are mapped through it, so every mark is
    /// drawn in the DISPLAYED space and stays on the picture. The identity shows the picture as
    /// the layer lays it out.
    struct FramePreviewConverter {
        let layer: AVCaptureVideoPreviewLayer
        let frameSize: CGSize
        let display: CGAffineTransform

        /// nil until there is a layer and a frame to convert for.
        init?(
            layer: AVCaptureVideoPreviewLayer?, frameSize: CGSize,
            display: CGAffineTransform = .identity
        ) {
            guard let layer, frameSize.width > 0, frameSize.height > 0 else { return nil }
            self.layer = layer
            self.frameSize = frameSize
            self.display = display
        }

        /// The rectangle in the displayed space, for a rectangle in frame pixels.
        func viewRect(of rect: CGRect) -> CGRect {
            layer.layerRectConverted(
                fromMetadataOutputRect: CGRect(
                    x: rect.minX / frameSize.width, y: rect.minY / frameSize.height,
                    width: rect.width / frameSize.width, height: rect.height / frameSize.height)
            ).applying(display)
        }

        /// The scale and offset that show `rect` (a rectangle in the layer's own coordinates)
        /// centred in a view of `viewSize`, as large as fits (aspect fit), clipped to the view.
        /// `rect` is kept centred on its own middle but trimmed to what the view actually shows
        /// of the layer, because the layer draws nothing outside its bounds. The identity when
        /// there is nothing sensible to show.
        static func fitTransform(of rect: CGRect, in viewSize: CGSize) -> CGAffineTransform {
            let centre = CGPoint(x: rect.midX, y: rect.midY)
            let halfWidth = min(rect.width / 2, centre.x, viewSize.width - centre.x)
            let halfHeight = min(rect.height / 2, centre.y, viewSize.height - centre.y)
            guard halfWidth >= 8, halfHeight >= 8, viewSize.width > 0, viewSize.height > 0 else {
                return .identity
            }
            let scale = min(viewSize.width / (halfWidth * 2), viewSize.height / (halfHeight * 2))
            return CGAffineTransform(translationX: viewSize.width / 2, y: viewSize.height / 2)
                .scaledBy(x: scale, y: scale)
                .translatedBy(x: -centre.x, y: -centre.y)
        }

        /// The transform that centres a confirmed field in a preview of `viewSize`, the identity
        /// while the field is not learned and confirmed (still learning, waiting for review or
        /// being adjusted: the uncropped picture, which the review's circle is mapped through).
        static func centringTransform(
            for field: SlideMovementInfo.Field, layer: AVCaptureVideoPreviewLayer?,
            viewSize: CGSize
        ) -> CGAffineTransform {
            guard !field.awaitingReview, let mask = field.state?.mask,
                let crop = FieldCentring.cropRect(for: mask, frameSize: field.frameSize),
                let plain = FramePreviewConverter(layer: layer, frameSize: field.frameSize)
            else { return .identity }
            return fitTransform(of: plain.viewRect(of: crop), in: viewSize)
        }

        func viewPoint(of point: CGPoint) -> CGPoint {
            viewRect(of: CGRect(origin: point, size: .zero)).origin
        }

        /// The frame pixel under a point of the displayed space.
        func framePoint(fromView point: CGPoint) -> CGPoint {
            let normalised = layer.metadataOutputRectConverted(
                fromLayerRect: CGRect(origin: point.applying(display.inverted()), size: .zero))
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
