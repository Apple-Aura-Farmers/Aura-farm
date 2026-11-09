//
//  LandOutlineEditorView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Where a helper marks out a farmer's land. The map opens on the phone's position; each tap
/// drops a dot, and the dots joined in the order they were placed are the edge of the land.
/// A dot can also be dropped exactly where the helper is standing, for walking the edge.
struct LandOutlineEditorView: View {
    @Binding var corners: [GeoPoint]

    @State private var location = LocationProvider()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        MapReader { proxy in
            Map(position: $position) {
                UserAnnotation()
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
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(.orange, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 2))
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
                if let coordinate = proxy.convert(point, from: .local) {
                    corners.append(GeoPoint(coordinate))
                }
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("Mark the land")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { location.start() }
        .onDisappear { location.stop() }
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: 12) {
            Text(status)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(isProblem ? Color.orange : Color.primary)

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
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private var isProblem: Bool { LandGeometry.crossesItself(corners) }

    private var status: String {
        if corners.isEmpty {
            return "Tap the map to drop a dot on each corner, going round the edge in order."
        }
        if corners.count < 3 {
            return "\(corners.count) of at least 3 corners. Keep tapping the corners."
        }
        if isProblem {
            return "The edges cross each other. Undo, then place the dots in order round the edge."
        }
        let area = LandGeometry.areaSquareMetres(of: corners) ?? 0
        return "\(corners.count) corners · \(LandGeometry.areaDescription(squareMetres: area))"
    }
}

#Preview {
    NavigationStack {
        LandOutlineEditorView(corners: .constant([]))
    }
}
