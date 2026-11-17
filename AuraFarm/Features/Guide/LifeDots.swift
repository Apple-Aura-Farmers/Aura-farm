import SwiftUI

extension Color {
    /// A palette colour (see `OrganismPalette`).
    init(_ colour: PaletteColour) {
        self.init(red: colour.red, green: colour.green, blue: colour.blue)
    }
}

/// How the life dots are drawn, so the lab's mini-map and the run summary's map look the same.
enum LifeDots {
    /// The dot's diameter in points.
    static let diameter = 5.0

    /// Draws one dot per organism: the type's colour with a thin dark outline, so it shows on any
    /// background. One path per type, so hundreds of dots stay cheap. With `highlight`, the other
    /// types fade.
    /// - Parameter place: a trail-space point on the canvas.
    static func draw(
        _ organisms: [RunMapOrganism], in context: inout GraphicsContext,
        place: (CGPoint) -> CGPoint, highlight: String? = nil, diameter: Double = LifeDots.diameter
    ) {
        for (label, group) in Dictionary(grouping: organisms, by: \.label).sorted(by: { $0.key < $1.key }) {
            var path = Path()
            for organism in group {
                let spot = place(organism.point)
                path.addEllipse(
                    in: CGRect(
                        x: spot.x - diameter / 2, y: spot.y - diameter / 2, width: diameter,
                        height: diameter))
            }
            let faded = highlight.map { $0 != label } ?? false
            let opacity = faded ? 0.2 : 1
            context.fill(
                path, with: .color(Color(OrganismPalette.colour(for: label)).opacity(opacity)))
            context.stroke(path, with: .color(.black.opacity(0.7 * opacity)), lineWidth: 0.75)
        }
    }
}

/// The legend under a map: the types present, with colour, name and count, most first. With a
/// `limit`, the top rows and "+N more". A tap on a row highlights that type (the others fade).
struct LifeLegendView: View {
    var counts: [String: Int]
    var limit: Int?
    @Binding var highlight: String?

    init(counts: [String: Int], limit: Int? = nil, highlight: Binding<String?> = .constant(nil)) {
        self.counts = counts
        self.limit = limit
        _highlight = highlight
    }

    var body: some View {
        let legend = LifeLegend.rows(counts: counts, limit: limit)
        HStack(spacing: 8) {
            ForEach(legend.rows) { row in
                HStack(spacing: 3) {
                    Circle()
                        .fill(Color(OrganismPalette.colour(for: row.label)))
                        .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 0.75))
                        .frame(width: 8, height: 8)
                    Text("\(row.display) \(row.count)").lineLimit(1)
                }
                .opacity(highlight.map { $0 == row.label ? 1 : 0.35 } ?? 1)
                .contentShape(Rectangle())
                .onTapGesture { highlight = highlight == row.label ? nil : row.label }
            }
            if legend.more > 0 { Text("+\(legend.more) more") }
        }
        .font(.caption2)
        .minimumScaleFactor(0.8)
    }
}
