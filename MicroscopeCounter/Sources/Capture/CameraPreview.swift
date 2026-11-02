import AVFoundation
import SwiftUI

/// Live camera preview, filling whatever it is given. The edges of the frame are cropped
/// away to do that, so the quality check sees a little more than the screen shows; what
/// matters is the round field in the middle, which is always on screen.
///
/// The boxes are drawn by the preview layer itself, because it is the only thing that knows
/// how the camera frame was rotated and cropped to fit the screen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    var boxes: [CountedBox] = []

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.show(boxes)
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees this type.
        layer as! AVCaptureVideoPreviewLayer
    }

    private let boxes = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(boxes)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        layer.addSublayer(boxes)
    }

    /// Draws one outline per counted organism, labelled with its id. There are only ever a
    /// few, so they are redrawn rather than kept and matched up.
    func show(_ counted: [CountedBox]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        boxes.frame = bounds
        for sublayer in boxes.sublayers ?? [] { sublayer.removeFromSuperlayer() }

        for item in counted {
            let rect = previewLayer.layerRectConverted(fromMetadataOutputRect: item.box)
            let outline = CALayer()
            outline.frame = rect
            outline.borderColor = UIColor.systemGreen.cgColor
            outline.borderWidth = 2
            outline.cornerRadius = 4
            boxes.addSublayer(outline)

            let caption = CATextLayer()
            caption.string = "\(item.id) \(item.label)"
            caption.fontSize = 11
            caption.foregroundColor = UIColor.white.cgColor
            caption.backgroundColor = UIColor.systemGreen.cgColor
            caption.alignmentMode = .center
            caption.contentsScale = UIScreen.main.scale
            caption.frame = CGRect(x: rect.minX, y: rect.minY - 15, width: rect.width, height: 14)
            boxes.addSublayer(caption)
        }
    }
}
