import SwiftUI

/// A small drawing of a farm's outline, for the list. It is just the shape of the land, with no
/// map behind it, so it costs nothing to draw and reads at a glance.
struct FarmOutlineThumbnail: View {
    let corners: [GeoPoint]

    var body: some View {
        ZStack {
            OutlineShape(corners: corners)
                .fill(Color.green.opacity(0.3))
            OutlineShape(corners: corners)
                .stroke(Color.green, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
        .padding(10)
        .frame(width: 52, height: 52)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
    }
}

/// The corners scaled to fill the space, with north at the top and the shape's proportions kept.
private struct OutlineShape: Shape {
    let corners: [GeoPoint]

    func path(in rect: CGRect) -> Path {
        guard corners.count >= 3, let middle = LandGeometry.centre(of: corners) else {
            return Path()
        }
        // A degree of longitude is shorter the further from the equator.
        let squeeze = cos(middle.latitude * .pi / 180)
        let xs = corners.map { CGFloat($0.longitude * squeeze) }
        // Latitude grows northward but the screen's y grows downward.
        let ys = corners.map { CGFloat(-$0.latitude) }
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max()
        else { return Path() }

        let width = max(maxX - minX, 0.000_000_1)
        let height = max(maxY - minY, 0.000_000_1)
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.minX + (rect.width - width * scale) / 2
        let originY = rect.minY + (rect.height - height * scale) / 2

        var path = Path()
        for index in corners.indices {
            let point = CGPoint(
                x: originX + (xs[index] - minX) * scale,
                y: originY + (ys[index] - minY) * scale)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    FarmOutlineThumbnail(
        corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1896),
            GeoPoint(latitude: -8.4105, longitude: 115.1889),
        ])
}
