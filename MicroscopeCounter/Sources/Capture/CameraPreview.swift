import AVFoundation
import SwiftUI

/// Live camera preview, filling whatever it is given. The edges of the frame are cropped
/// away to do that, so the quality check sees a little more than the screen shows; what
/// matters is the round field in the middle, which is always on screen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass guarantees this type.
        layer as! AVCaptureVideoPreviewLayer
    }
}
