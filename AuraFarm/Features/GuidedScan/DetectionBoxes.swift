import SwiftUI

/// The boxes from the engine, read in a view of their own so they redraw as the engine publishes
/// them (a read inside the page's picture closure is not tracked).
struct LiveDetectionBoxes: View {
    var model: ScanEngine
    var converter: FramePreviewConverter?

    var body: some View {
        DetectionBoxes(info: model.liveBoxes) { converter?.viewPolygon(of: $0) ?? [] }
    }
}

/// The detector's boxes over the picture: green counted, grey seen once, blue a repeat (already
/// on the map). `polygon` turns a box in frame pixels into points of the displayed space, so
/// the boxes go through the same centring and straightening as the picture.
struct DetectionBoxes: View {
    var info: LiveCountInfo
    var polygon: (CGRect) -> [CGPoint]

    static func colour(_ status: LiveOrganismCounter.BoxStatus) -> Color {
        switch status {
        case .counted: .green
        case .seenOnce: .gray
        case .repeatOnMap: .blue
        case .notCounted: .yellow
        }
    }

    var body: some View {
        Canvas { context, _ in
            for box in info.isPreviewing ? info.previewBoxes : info.boxes {
                let points = polygon(box.rect)
                guard let first = points.first else { continue }
                var path = Path()
                path.addLines(points)
                path.closeSubpath()
                let colour = Self.colour(box.status)
                context.stroke(path, with: .color(colour), lineWidth: 2)
                let caption = Text(
                    "\(box.id) \(OrganismDisplayName.label(box.label)) \(Int(box.confidence * 100))%"
                        + (box.status == .notCounted ? " not counted" : "")
                )
                .font(.caption2.bold())
                .foregroundStyle(colour)
                context.draw(caption, at: CGPoint(x: first.x, y: first.y - 8), anchor: .bottomLeading)
            }
        }
        .allowsHitTesting(false)
    }
}
