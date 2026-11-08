import SwiftUI

/// Where each frame of a sweep sits on the slide. The rows alternate direction, so the
/// slide is only ever nudged on from where it already is rather than carried back to the
/// start of the next row.
///
/// Shared by the diagram in the guide and by the grid a saved sweep is laid out in, so the
/// two cannot drift apart.
struct SweepLayout {
    var columns: Int
    var rows: Int

    init(thresholds: SweepThresholds = SweepThresholds(), frameCount: Int? = nil) {
        columns = max(thresholds.framesPerRow, 1)
        let frames = max(frameCount ?? thresholds.framesPerSweep, 1)
        // A sweep that stopped early has a part row at the end, which still needs a row.
        rows = Int((Double(frames) / Double(columns)).rounded(.up))
    }

    func position(of index: Int) -> (row: Int, column: Int) {
        let row = index / columns
        let along = index % columns
        return (row: row, column: row.isMultiple(of: 2) ? along : columns - 1 - along)
    }

    /// The frame indices of one row, in the order the slide passes through them.
    func indices(inRow row: Int, frameCount: Int) -> [Int] {
        let start = row * columns
        let indices = (start..<min(start + columns, frameCount)).map { $0 }
        return row.isMultiple(of: 2) ? indices : indices.reversed()
    }
}

/// The route the slide is walked along: across a row, down one step, back the other way.
///
/// Drawn from the sweep's own settings rather than a fixed picture, so a change to
/// `framesPerSweep` or `framesPerRow` shows up here instead of quietly disagreeing with it.
/// The grey bands between the fields are the overlap: neighbouring frames have to share
/// some ground or the stitcher cannot line them up.
struct SweepPatternView: View {
    var thresholds = SweepThresholds()

    private var layout: SweepLayout { SweepLayout(thresholds: thresholds) }
    private var columns: Int { layout.columns }
    private var rows: Int { layout.rows }

    var body: some View {
        Canvas { context, size in
            let cellWidth = size.width / Double(columns)
            let cellHeight = size.height / Double(rows)
            let band = min(cellWidth, cellHeight) * 0.12

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.fieldBackground))

            // The overlap between one field and the next, where both frames see the slide.
            for column in 1..<max(columns, 2) {
                let x = Double(column) * cellWidth
                context.fill(
                    Path(CGRect(x: x - band / 2, y: 0, width: band, height: size.height)),
                    with: .color(.fieldOverlap))
            }
            for row in 1..<max(rows, 2) {
                let y = Double(row) * cellHeight
                context.fill(
                    Path(CGRect(x: 0, y: y - band / 2, width: size.width, height: band)),
                    with: .color(.fieldOverlap))
            }

            for index in 0..<(columns * rows) {
                let place = position(of: index)
                let centre = CGPoint(
                    x: (Double(place.column) + 0.5) * cellWidth,
                    y: (Double(place.row) + 0.35) * cellHeight)
                context.draw(
                    Text("\(index)")
                        .font(.system(size: min(cellWidth, cellHeight) * 0.42, weight: .medium))
                        .foregroundStyle(.primary),
                    at: centre)
            }

            let route = waypoints(cellWidth: cellWidth, cellHeight: cellHeight)
            context.stroke(
                path(through: route, radius: min(cellWidth, cellHeight) * 0.22),
                with: .color(.sweepRoute),
                style: StrokeStyle(
                    lineWidth: max(min(cellWidth, cellHeight) * 0.06, 2),
                    lineCap: .round, lineJoin: .round))

            if let start = route.first {
                context.fill(diamond(at: start, radius: cellHeight * 0.07), with: .color(.sweepRoute))
            }
            if route.count >= 2 {
                context.fill(
                    arrowHead(
                        at: route[route.count - 1], from: route[route.count - 2],
                        size: cellHeight * 0.16),
                    with: .color(.sweepRoute))
            }
        }
        .aspectRatio(Double(columns) / Double(rows), contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(
            "The sweep walks \(rows) rows of \(columns) fields, left to right along the first "
                + "row, down one, then back the other way.")
    }

    func position(of index: Int) -> (row: Int, column: Int) { layout.position(of: index) }

    /// The corners of the route, in order. It runs below the numbers rather than through
    /// them, the way a finger would trace it.
    private func waypoints(cellWidth: Double, cellHeight: Double) -> [CGPoint] {
        let inset = cellWidth * 0.3
        var points: [CGPoint] = []
        for row in 0..<rows {
            let y = (Double(row) + 0.72) * cellHeight
            let left = inset
            let right = Double(columns) * cellWidth - inset
            points.append(
                contentsOf: row.isMultiple(of: 2)
                    ? [
                        CGPoint(x: left, y: y), CGPoint(x: right, y: y),
                    ]
                    : [
                        CGPoint(x: right, y: y), CGPoint(x: left, y: y),
                    ])
        }
        return points
    }

    private func path(through points: [CGPoint], radius: Double) -> Path {
        var path = Path()
        guard let first = points.first, points.count >= 2 else { return path }
        path.move(to: first)
        for index in 1..<(points.count - 1) {
            path.addArc(
                tangent1End: points[index], tangent2End: points[index + 1], radius: radius)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private func diamond(at point: CGPoint, radius: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: point.x, y: point.y - radius))
        path.addLine(to: CGPoint(x: point.x + radius, y: point.y))
        path.addLine(to: CGPoint(x: point.x, y: point.y + radius))
        path.addLine(to: CGPoint(x: point.x - radius, y: point.y))
        path.closeSubpath()
        return path
    }

    private func arrowHead(at tip: CGPoint, from previous: CGPoint, size: Double) -> Path {
        let angle = atan2(tip.y - previous.y, tip.x - previous.x)
        let spread = 0.45
        var path = Path()
        path.move(to: tip)
        path.addLine(
            to: CGPoint(
                x: tip.x - size * cos(angle - spread), y: tip.y - size * sin(angle - spread)))
        path.addLine(
            to: CGPoint(
                x: tip.x - size * cos(angle + spread), y: tip.y - size * sin(angle + spread)))
        path.closeSubpath()
        return path
    }
}

extension ShapeStyle where Self == Color {
    fileprivate static var fieldBackground: Color { Color(white: 0.9) }
    fileprivate static var fieldOverlap: Color { Color(white: 0.78) }
    fileprivate static var sweepRoute: Color { Color(red: 0.96, green: 0.57, blue: 0.16) }
}

#Preview {
    SweepPatternView()
        .padding()
}
