import AuraFarmKit
import MapKit
import SwiftData
import SwiftUI

/// A farm's fields on satellite imagery, each outlined and named. Clicking a name opens the field.
struct FarmMapView: View {
    let fields: [Field]
    var onOpenField: (Field) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Map")
                .font(.headline)
            if let region = MapDefaults.region(around: fields) {
                Map(initialPosition: .region(region)) {
                    ForEach(drawnFields) { drawn in
                        MapPolygon(coordinates: drawn.outline.coordinates)
                            .foregroundStyle(.yellow.opacity(0.2))
                            .stroke(.yellow, lineWidth: 2)
                    }
                    ForEach(drawnFields) { drawn in
                        Annotation("", coordinate: drawn.outline.center.coordinate) {
                            Button(drawn.field.name) {
                                onOpenField(drawn.field)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .help("Open \(drawn.field.name)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.imagery(elevation: .flat))
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                // A new outline moves the map to take it in.
                .id(outlineKey)
                if drawnFields.count < fields.count {
                    Text("\(fields.count - drawnFields.count) of \(fields.count) fields not drawn yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No field is drawn yet. Open a field and choose Draw Boundary to see the farm here.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct DrawnField: Identifiable {
        var field: Field
        var outline: FieldBoundary
        var id: PersistentIdentifier { field.persistentModelID }
    }

    private var drawnFields: [DrawnField] {
        fields.compactMap { field in
            field.boundary.map { DrawnField(field: field, outline: $0) }
        }
    }

    /// Changes whenever any outline does.
    private var outlineKey: [Data?] {
        fields.map(\.boundaryData)
    }
}
