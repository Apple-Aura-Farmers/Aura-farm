import SwiftUI

/// The whole run on one map: the path, the edges and the organisms the helper's count includes
/// as dots, fitted to the view. Drawn from a `RunMapContent`, so the run summary and a saved
/// record draw the same way; the helper screen can reuse it. Not part of the lab (no DEBUG).
struct RunMapView: View {
    var content: RunMapContent
    /// A type to highlight; the others fade.
    var highlight: String?

    var body: some View {
        Canvas { context, size in draw(&context, size) }
            .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.55)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func draw(_ context: inout GraphicsContext, _ size: CGSize) {
        guard let bounds = content.screenBounds else { return }
        let margin = 14.0
        // At least 3 fields across, so a run of one spot is not blown up.
        let width = max(Double(bounds.width), 3)
        let height = max(Double(bounds.height), 3)
        let scale = min(
            (size.width - 2 * margin) / width, (size.height - 2 * margin) / height)
        let centre = CGPoint(x: bounds.midX, y: bounds.midY)
        func place(_ point: CGPoint) -> CGPoint {
            let moved = content.onScreen(point)
            return CGPoint(
                x: size.width / 2 + (moved.x - centre.x) * scale,
                y: size.height / 2 + (moved.y - centre.y) * scale)
        }

        for edge in content.edges {
            if edge.kind == "point" {
                let spot = place(CGPoint(x: edge.x1, y: edge.y1))
                context.fill(
                    Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4)),
                    with: .color(.cyan))
                continue
            }
            var line = Path()
            line.move(to: place(CGPoint(x: edge.x1, y: edge.y1)))
            line.addLine(to: place(CGPoint(x: edge.x2, y: edge.y2)))
            context.stroke(
                line, with: .color(.cyan.opacity(0.6)), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
        }
        if content.path.count > 1 {
            var trail = Path()
            trail.move(to: place(content.path[0]))
            for point in content.path.dropFirst() { trail.addLine(to: place(point)) }
            context.stroke(trail, with: .color(.yellow.opacity(0.55)), lineWidth: 1.2)
        }
        LifeDots.draw(content.organisms, in: &context, place: place, highlight: highlight)
    }
}

#if DEBUG
    /// About 60 dots of 6 types along a snaking path inside a 5 x 4 field slip.
    private func previewContent(types: Int = 6, dots: Int = 60) -> RunMapContent {
        let labels = ["Volvox", "Nematode", "Euglenoid", "Arcellinida", "Digononta", "Rotifer"]
        let path = (0..<200).map {
            CGPoint(x: Double($0) / 40, y: 2 + 1.8 * sin(Double($0) / 7))
        }
        let organisms = (0..<dots).map { index in
            RunMapOrganism(
                label: labels[index % types], x: Double((index * 37) % 50) / 10,
                y: 0.3 + Double((index * 53) % 38) / 10, column: index / 10 + 1,
                seconds: Double(index))
        }
        let edges = [
            RunMapEdge(kind: "top", x1: 0, y1: 0, x2: 5, y2: 0),
            RunMapEdge(kind: "bottom", x1: 0, y1: 4.2, x2: 5, y2: 4.2),
            RunMapEdge(kind: "left", x1: 0, y1: 0, x2: 0, y2: 4.2),
            RunMapEdge(kind: "right", x1: 5, y1: 0, x2: 5, y2: 4.2),
        ]
        return RunMapContent(path: path, edges: edges, organisms: organisms)
    }

    private func previewCounts(_ content: RunMapContent) -> [String: Int] {
        Dictionary(grouping: content.organisms, by: \.label).mapValues(\.count)
    }

    private struct HighlightPreview: View {
        @State private var highlight: String? = "Volvox"
        var body: some View {
            let content = previewContent()
            VStack(alignment: .leading) {
                RunMapView(content: content, highlight: highlight).frame(height: 260)
                LifeLegendView(counts: previewCounts(content), highlight: $highlight)
            }
            .padding()
        }
    }

    #Preview("Summary map: Volvox highlighted") { HighlightPreview() }

    #Preview("Mini-map: about 60 dots of 6 types") {
        let content = previewContent()
        VStack(spacing: 4) {
            RunMapView(content: content).frame(width: 160, height: 160)
            LifeLegendView(counts: previewCounts(content), limit: 3)
        }
        .padding()
    }

    #Preview("Legend at a narrow width, +N more") {
        let counts = previewCounts(previewContent())
        VStack(alignment: .leading, spacing: 8) {
            ForEach([320.0, 200.0, 150.0], id: \.self) { width in
                LifeLegendView(counts: counts, limit: 3).frame(width: width, alignment: .leading)
            }
        }
        .padding()
    }
#endif
