import AuraFarmKit
import MapKit
import SwiftUI

/// Draws a field's outline on satellite imagery: click each corner in turn, then save.
///
/// The farm's other fields are shown faintly, so neighbouring paddies line up. The area of the
/// outline can replace the field's typed-in area, which the fertilizer doses are worked out from.
struct FieldBoundaryEditorView: View {
    @Bindable var field: Field

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var corners: [FieldPoint] = []
    @State private var camera: MapCameraPosition = .region(MapDefaults.startRegion)
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var searchFailed = false
    @State private var usesDrawnArea = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            MapReader { proxy in
                Map(position: $camera) {
                    ForEach(Array(otherOutlines.enumerated()), id: \.offset) { _, outline in
                        MapPolygon(coordinates: outline.coordinates)
                            .foregroundStyle(.white.opacity(0.12))
                            .stroke(.white.opacity(0.7), lineWidth: 1)
                    }
                    if corners.count >= FieldBoundary.minimumCorners {
                        MapPolygon(coordinates: drawn.coordinates)
                            .foregroundStyle(.yellow.opacity(0.25))
                            .stroke(.yellow, lineWidth: 2)
                    } else if corners.count == 2 {
                        MapPolyline(coordinates: drawn.coordinates)
                            .stroke(.yellow, lineWidth: 2)
                    }
                    ForEach(Array(corners.enumerated()), id: \.offset) { _, corner in
                        Annotation("", coordinate: corner.coordinate) {
                            Circle()
                                .fill(.yellow)
                                .stroke(.black.opacity(0.6), lineWidth: 1)
                                .frame(width: 10, height: 10)
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.imagery(elevation: .flat))
                .onTapGesture { location in
                    if let coordinate = proxy.convert(location, from: .local) {
                        corners.append(FieldPoint(coordinate))
                    }
                }
            }
            footer
        }
        .frame(width: 900, height: 660)
        .onAppear(perform: load)
    }

    // MARK: - Parts

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Draw \(field.name)")
                .font(.headline)
            Text("Find the paddy, then click each corner in order. Drag to move the map; scroll to zoom.")
                .foregroundStyle(.secondary)
            HStack {
                TextField("Village or place", text: $searchText, prompt: Text("For example, Jatiluwih"))
                    .onSubmit(search)
                    .frame(maxWidth: 320)
                Button("Find", action: search)
                    .disabled(searchText.trimmingCharacters(in: .whitespaces).isEmpty || isSearching)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
                if searchFailed {
                    Text("Not found. Try a nearby village or town.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 12) {
            Button("Undo Corner") {
                corners.removeLast()
            }
            .disabled(corners.isEmpty)
            Button("Clear") {
                corners.removeAll()
            }
            .disabled(corners.isEmpty)

            Text(status)
                .foregroundStyle(.secondary)
            if let area = drawn.areaHectares {
                Toggle("Use as the field's area", isOn: $usesDrawnArea)
                    .help("The fertilizer doses for the whole field are worked out from the area")
                    .disabled(Self.rounded(area) <= 0)
            }

            Spacer()
            Button("Cancel", role: .cancel) {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            Button("Save") {
                save()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(20)
    }

    // MARK: - State

    private var drawn: FieldBoundary {
        FieldBoundary(corners: corners)
    }

    /// The farm's other fields, to draw faintly behind this one.
    private var otherFields: [Field] {
        (field.farm?.fields ?? []).filter { $0.persistentModelID != field.persistentModelID }
    }

    private var otherOutlines: [FieldBoundary] {
        otherFields.compactMap(\.boundary)
    }

    /// No corners removes the outline; one or two is not an outline yet.
    private var canSave: Bool {
        corners.isEmpty || drawn.isComplete
    }

    private var status: String {
        switch corners.count {
        case 0:
            return field.boundary == nil ? "No corners yet." : "Saving with no corners removes the outline."
        case 1, 2:
            return "\(corners.count) of at least 3 corners."
        default:
            guard let area = drawn.areaHectares else { return "" }
            return "\(corners.count) corners, about \(Self.rounded(area).formatted(.number)) ha."
        }
    }

    /// Hectares to two decimals, about a 10 m by 10 m square: finer than a click on the map.
    private static func rounded(_ hectares: Double) -> Double {
        (hectares * 100).rounded() / 100
    }

    // MARK: - Actions

    private func load() {
        corners = field.boundary?.corners ?? []
        usesDrawnArea = field.areaHectares == nil
        searchText = field.farm?.location ?? ""
        if let region = field.boundary?.bounds?.region ?? MapDefaults.region(around: otherFields) {
            camera = .region(region)
        } else {
            search()
        }
    }

    private func search() {
        let place = searchText
        guard !place.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        searchFailed = false
        Task {
            let region = await MapDefaults.region(searchingFor: place)
            isSearching = false
            if let region {
                camera = .region(region)
            } else {
                searchFailed = true
            }
        }
    }

    private func save() {
        field.boundary = corners.isEmpty ? nil : drawn
        if usesDrawnArea, let area = drawn.areaHectares, Self.rounded(area) > 0 {
            field.areaHectares = Self.rounded(area)
        }
        try? modelContext.save()
        dismiss()
    }
}
