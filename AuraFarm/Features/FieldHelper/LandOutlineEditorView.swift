//
//  LandOutlineEditorView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Where a helper marks out a farmer's land. The map opens on the phone's position (or on the
/// existing outline when editing); each tap drops a dot, and the dots joined in the order they
/// were placed are the edge of the land. A dot can also be dropped exactly where the helper is
/// standing, for walking the edge.
///
/// Nothing is kept until the helper taps **Confirm outline**. Leaving any other way throws the
/// changes away, after asking if anything was changed.
struct LandOutlineEditorView: View {
    /// Land already mapped, drawn on the map so the new outline can be kept clear of it.
    let neighbours: [Neighbour]
    let onConfirm: ([GeoPoint]) -> Void

    @State private var corners: [GeoPoint]
    @State private var position: MapCameraPosition
    @State private var location = LocationProvider()
    @State private var confirmDiscard = false
    /// The corner being dragged, and where it sat on screen when the drag began.
    @State private var drag: (index: Int, start: CGPoint)?
    @Environment(\.dismiss) private var dismiss

    private let startingCorners: [GeoPoint]

    init(
        corners: [GeoPoint], neighbours: [Neighbour],
        onConfirm: @escaping ([GeoPoint]) -> Void
    ) {
        self.startingCorners = corners
        self.neighbours = neighbours
        self.onConfirm = onConfirm
        _corners = State(initialValue: corners)
        // Editing opens on the existing land; a new outline opens on where the phone is.
        if let region = LandGeometry.region(fitting: corners) {
            _position = State(initialValue: .region(region))
        } else {
            _position = State(initialValue: .userLocation(fallback: .automatic))
        }
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $position, interactionModes: drag == nil ? .all : []) {
                UserAnnotation()

                ForEach(neighbours) { neighbour in
                    MapPolygon(coordinates: neighbour.corners.map(\.coordinate))
                        .foregroundStyle(.blue.opacity(0.25))
                        .stroke(.cyan, lineWidth: 2)
                    if let middle = LandGeometry.centre(of: neighbour.corners) {
                        Annotation(
                            neighbour.label, coordinate: middle.coordinate, anchor: .center
                        ) {
                            Text(neighbour.label)
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.6), in: Capsule())
                        }
                        .annotationTitles(.hidden)
                    }
                }

                if corners.count >= 3 {
                    MapPolygon(coordinates: corners.map(\.coordinate))
                        .foregroundStyle(.green.opacity(0.3))
                        .stroke(.white, lineWidth: 2)
                } else if corners.count == 2 {
                    MapPolyline(coordinates: corners.map(\.coordinate))
                        .stroke(.white, lineWidth: 2)
                }
                ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                    Annotation(
                        "Corner \(index + 1)", coordinate: corner.coordinate, anchor: .center
                    ) {
                        let isDragging = drag?.index == index
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.orange, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .scaleEffect(isDragging ? 1.35 : 1)
                            .animation(.spring(duration: 0.2), value: isDragging)
                            // A bigger area to grab than the dot itself, for a thumb.
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                            .gesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                    .onChanged { value in
                                        moveCorner(index, by: value.translation, using: proxy)
                                    }
                                    .onEnded { _ in drag = nil }
                            )
                            .accessibilityLabel("Corner \(index + 1)")
                            .accessibilityHint("Drag to move this corner")
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.hybrid)
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                // A tap on an existing dot is for that dot, not a new corner beside it.
                let onADot = corners.contains { corner in
                    guard let spot = proxy.convert(corner.coordinate, to: .local) else {
                        return false
                    }
                    return hypot(spot.x - point.x, spot.y - point.y) < 22
                }
                if !onADot, let coordinate = proxy.convert(point, from: .local) {
                    corners.append(GeoPoint(coordinate))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("Mark the land")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    if corners == startingCorners {
                        dismiss()
                    } else {
                        confirmDiscard = true
                    }
                }
            }
        }
        .confirmationDialog(
            "Discard your changes to the outline?", isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard changes", role: .destructive) { dismiss() }
            Button("Keep editing", role: .cancel) {}
        }
        .onAppear { location.start() }
        .onDisappear { location.stop() }
    }

    // MARK: Dragging corners

    /// Moves a corner to follow the finger. The corner's screen position is noted when the drag
    /// starts and the finger's movement added to it, so the dot keeps its distance from the
    /// finger instead of jumping to sit under it.
    private func moveCorner(_ index: Int, by translation: CGSize, using proxy: MapProxy) {
        guard corners.indices.contains(index) else { return }
        if drag?.index != index {
            guard let start = proxy.convert(corners[index].coordinate, to: .global) else {
                return
            }
            drag = (index, start)
        }
        guard let start = drag?.start,
            let coordinate = proxy.convert(
                CGPoint(x: start.x + translation.width, y: start.y + translation.height),
                from: .global)
        else { return }
        corners[index] = GeoPoint(coordinate)
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Text(status)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(crossesItself ? Color.orange : Color.primary)

            if !corners.isEmpty {
                Text("Drag a dot to move it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !overlapping.isEmpty {
                Text(overlapWarning)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.orange)
            }

            if location.isDenied {
                Text("Location is off, so the map will not open where you are.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let settings = URL(string: UIApplication.openSettingsURLString) {
                    Link("Open Settings", destination: settings)
                        .font(.footnote)
                }
            }

            HStack(spacing: 10) {
                Button {
                    corners.removeLast()
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(corners.isEmpty)

                Button {
                    if let here = location.location {
                        corners.append(GeoPoint(here.coordinate))
                    }
                } label: {
                    Label("Dot here", systemImage: "location.fill")
                }
                .disabled(location.location == nil)

                Button(role: .destructive) {
                    corners.removeAll()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(corners.isEmpty)
            }
            .buttonStyle(.bordered)

            Button {
                onConfirm(corners)
                dismiss()
            } label: {
                Text(overlapping.isEmpty ? "Confirm outline" : "Confirm anyway")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canConfirm)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var crossesItself: Bool { LandGeometry.crossesItself(corners) }

    private var canConfirm: Bool { corners.count >= 3 && !crossesItself }

    private var overlapping: [Neighbour] {
        neighbours.filter { LandGeometry.overlap(corners, $0.corners) }
    }

    private var overlapWarning: String {
        let names = overlapping.map(\.label).formatted(.list(type: .and))
        return "This outline overlaps \(names)'s land. Move the dots so it stays on this "
            + "farmer's own land, or confirm anyway if the overlap is only GPS error."
    }

    private var status: String {
        if corners.isEmpty {
            return "Tap the map to drop a dot on each corner, going round the edge in order."
        }
        if corners.count < 3 {
            return "\(corners.count) of at least 3 corners. Keep tapping the corners."
        }
        if crossesItself {
            return "The edges cross each other. Undo, then place the dots in order round the edge."
        }
        let area = LandGeometry.areaSquareMetres(of: corners) ?? 0
        return "\(corners.count) corners · \(LandGeometry.areaDescription(squareMetres: area))"
    }
}

#Preview {
    NavigationStack {
        LandOutlineEditorView(
            corners: [],
            neighbours: [
                Neighbour(
                    id: UUID(),
                    label: "Subak Jatiluwih",
                    corners: [
                        GeoPoint(latitude: -8.4095, longitude: 115.1889),
                        GeoPoint(latitude: -8.4095, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1889),
                    ])
            ],
            onConfirm: { _ in })
    }
}
