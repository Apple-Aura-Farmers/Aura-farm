//
//  LandMapView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// A satellite map of a farm's land: each outline filled lightly, with a dot on every corner
/// where there is only one. Used to show a farm back to the helper, in the form and on the
/// farm's page.
struct LandMapView: View {
    /// The outlines to draw, each a ring of corners in the order they go round the edge.
    let outlines: [[GeoPoint]]
    /// Whether the map can be panned and zoomed. Off in the form, where it is only a preview.
    var isInteractive = false

    init(corners: [GeoPoint], isInteractive: Bool = false) {
        self.init(outlines: [corners], isInteractive: isInteractive)
    }

    init(outlines: [[GeoPoint]], isInteractive: Bool = false) {
        self.outlines = outlines
        self.isInteractive = isInteractive
    }

    var body: some View {
        Map(initialPosition: initialPosition, interactionModes: isInteractive ? [.pan, .zoom] : []) {
            ForEach(Array(outlines.enumerated()), id: \.offset) { _, corners in
                if corners.count >= 3 {
                    MapPolygon(coordinates: corners.map(\.coordinate))
                        .foregroundStyle(.green.opacity(0.3))
                        .stroke(.white, lineWidth: 2)
                }
            }
            // Only with one outline: a dot on every corner of every plot would read as a mess.
            if let only = singleOutline {
                ForEach(Array(only.enumerated()), id: \.offset) { index, corner in
                    Annotation(
                        "Corner \(index + 1)", coordinate: corner.coordinate, anchor: .center
                    ) {
                        Circle()
                            .fill(.orange)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(.hybrid)
        .accessibilityElement()
        .accessibilityLabel(label)
    }

    /// The one outline, when that is all there is, so its corners can be dotted.
    private var singleOutline: [GeoPoint]? {
        outlines.count == 1 ? outlines[0] : nil
    }

    private var label: String {
        if let singleOutline {
            return "Map of the land with \(singleOutline.count) corners marked"
        }
        return "Map of \(outlines.count) plots of land"
    }

    private var initialPosition: MapCameraPosition {
        guard let region = LandGeometry.region(fitting: outlines.flatMap { $0 }) else {
            return .automatic
        }
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
