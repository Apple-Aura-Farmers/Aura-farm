import AuraFarmKit
import MapKit
import SwiftUI

/// The field's outline on satellite imagery, with its drawn and entered areas, on the field page.
struct FieldMapPreview: View {
    let field: Field
    /// nil for someone who cannot change the field, which hides the button.
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Boundary")
                    .font(.headline)
                Spacer()
                if let onEdit {
                    Button(field.boundary == nil ? "Draw Boundary" : "Edit Boundary", action: onEdit)
                }
            }
            if let outline = field.boundary, let bounds = outline.bounds {
                Map(initialPosition: .region(bounds.region), interactionModes: []) {
                    MapPolygon(coordinates: outline.coordinates)
                        .foregroundStyle(.yellow.opacity(0.2))
                        .stroke(.yellow, lineWidth: 2)
                }
                .mapStyle(.imagery(elevation: .flat))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .id(field.boundaryData)
                Text(areaNote(for: outline))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not drawn on the map yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "About 0.58 ha drawn · 0.6 ha entered"
    private func areaNote(for outline: FieldBoundary) -> String {
        var parts: [String] = []
        if let drawn = outline.areaHectares {
            parts.append("About \(drawn.formatted(.number.precision(.fractionLength(2)))) ha drawn")
        }
        if let entered = field.areaHectares {
            parts.append("\(entered.formatted(.number)) ha entered")
        } else {
            parts.append("No area entered")
        }
        return parts.joined(separator: " · ")
    }
}
