import AuraFarmKit
import MapKit
import SwiftData
import SwiftUI

/// A farm's fields on satellite imagery, each outlined and named. Tapping a name opens the field.
struct FarmMapView: View {
    let fields: [Field]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let region = MapDefaults.region(around: fields) {
                Map(initialPosition: .region(region)) {
                    ForEach(drawnFields) { drawn in
                        MapPolygon(coordinates: drawn.outline.coordinates)
                            .foregroundStyle(.yellow.opacity(0.2))
                            .stroke(.yellow, lineWidth: 2)
                    }
                    ForEach(drawnFields) { drawn in
                        Annotation("", coordinate: drawn.outline.center.coordinate) {
                            NavigationLink(value: drawn.field) {
                                Text(drawn.field.name)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
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
                Text("No field is drawn on the map yet. Open a field and choose Draw Boundary.")
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
