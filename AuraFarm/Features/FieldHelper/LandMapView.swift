//
//  LandMapView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// A satellite map of a farm's land: the outline, filled lightly, with a dot on each corner.
/// Used to show a farm back to the helper, in the form and on the farm's page.
struct LandMapView: View {
    let corners: [GeoPoint]
    /// Whether the map can be panned and zoomed. Off in the form, where it is only a preview.
    var isInteractive = false

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: isInteractive ? [.pan, .zoom] : []) {
            if corners.count >= 3 {
                MapPolygon(coordinates: corners.map(\.coordinate))
                    .foregroundStyle(.green.opacity(0.3))
                    .stroke(.white, lineWidth: 2)
            }
            ForEach(Array(corners.enumerated()), id: \.offset) { index, corner in
                Annotation("Corner \(index + 1)", coordinate: corner.coordinate, anchor: .center) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.hybrid)
        .accessibilityElement()
        .accessibilityLabel("Map of the land with \(corners.count) corners marked")
    }

    private var initialPosition: MapCameraPosition {
        guard let region = LandGeometry.region(fitting: corners) else { return .automatic }
        return .region(region)
    }
}

#Preview {
    LandMapView(
        corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1889),
        ],
        isInteractive: true
    )
}
