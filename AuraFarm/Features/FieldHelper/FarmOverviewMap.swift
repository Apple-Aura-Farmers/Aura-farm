//
//  FarmOverviewMap.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Every saved farm on one satellite map. Tapping a farm's land, or its name, opens that farm.
struct FarmsOverviewMap: View {
    let farms: [Farm]
    /// Called with the farm the helper tapped.
    let onOpen: (Farm) -> Void

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: initialPosition) {
                ForEach(farms) { farm in
                    MapPolygon(coordinates: farm.corners.map(\.coordinate))
                        .foregroundStyle(.green.opacity(0.35))
                        .stroke(.white, lineWidth: 2)
                    if let middle = LandGeometry.centre(of: farm.corners) {
                        Annotation(farm.farmerName, coordinate: middle.coordinate, anchor: .center) {
                            Button {
                                onOpen(farm)
                            } label: {
                                Text(farm.farmerName)
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(.black.opacity(0.6), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.hybrid)
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local),
                    let farm = farm(at: GeoPoint(coordinate))
                else { return }
                onOpen(farm)
            }
        }
        .overlay(alignment: .bottomLeading) {
            Text("Tap a farm to open it")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .padding(8)
                .allowsHitTesting(false)
        }
    }

    /// The farm whose land contains the spot. Where outlines overlap, the smaller farm wins,
    /// so a small plot inside a big one can still be reached.
    private func farm(at spot: GeoPoint) -> Farm? {
        farms
            .filter { LandGeometry.contains(spot, in: $0.corners) }
            .min { ($0.areaSquareMetres ?? 0) < ($1.areaSquareMetres ?? 0) }
    }

    /// Opens with every farm in view.
    private var initialPosition: MapCameraPosition {
        guard let region = LandGeometry.region(fitting: farms.flatMap(\.corners)) else {
            return .automatic
        }
        return .region(region)
    }
}

#Preview {
    FarmsOverviewMap(
        farms: [
            Farm(
                farmerName: "Pak Wayan",
                corners: [
                    GeoPoint(latitude: -8.4095, longitude: 115.1889),
                    GeoPoint(latitude: -8.4095, longitude: 115.1900),
                    GeoPoint(latitude: -8.4105, longitude: 115.1900),
                    GeoPoint(latitude: -8.4105, longitude: 115.1889),
                ]),
            Farm(
                farmerName: "Ibu Made",
                corners: [
                    GeoPoint(latitude: -8.4095, longitude: 115.1905),
                    GeoPoint(latitude: -8.4095, longitude: 115.1920),
                    GeoPoint(latitude: -8.4108, longitude: 115.1920),
                    GeoPoint(latitude: -8.4108, longitude: 115.1905),
                ]),
        ],
        onOpen: { _ in }
    )
}
