//
//  FarmOverviewMap.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Every saved farm on one satellite map, a shape for each of its plots. Tapping a farm's land,
/// or its name, opens that farm. Plain imagery with no road or place labels, so the farms are
/// the only thing drawn on it.
struct FarmsOverviewMap: View {
    let farms: [Farm]
    /// Called with the farm the helper tapped.
    let onOpen: (Farm) -> Void

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: initialPosition) {
                ForEach(farms) { farm in
                    ForEach(farm.plots) { plot in
                        MapPolygon(coordinates: plot.corners.map(\.coordinate))
                            .foregroundStyle(.green.opacity(0.35))
                            .stroke(.white, lineWidth: 2)
                    }
                    if let middle = LandGeometry.centre(of: farm.allCorners) {
                        Annotation(farm.name, coordinate: middle.coordinate, anchor: .center) {
                            Button {
                                onOpen(farm)
                            } label: {
                                Text(farm.name)
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
            .mapStyle(.imagery)
            .mapControls {
                MapCompass()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local),
                    let farm = farm(at: GeoPoint(coordinate))
                else { return }
                onOpen(farm)
            }
        }
    }

    /// The farm with a plot containing the spot. Where plots overlap, the smaller one wins, so
    /// a small plot inside a big one can still be reached.
    private func farm(at spot: GeoPoint) -> Farm? {
        farms
            .flatMap { farm in
                farm.plots
                    .filter { LandGeometry.contains(spot, in: $0.corners) }
                    .map { (farm: farm, area: $0.areaSquareMetres ?? 0) }
            }
            .min { $0.area < $1.area }?
            .farm
    }

    /// Opens with every farm in view.
    private var initialPosition: MapCameraPosition {
        guard let region = LandGeometry.region(fitting: farms.flatMap(\.allCorners)) else {
            return .automatic
        }
        return .region(region)
    }
}

#Preview {
    FarmsOverviewMap(
        farms: [
            Farm(
                name: "Subak Jatiluwih",
                farmerName: "Pak Wayan",
                plots: [
                    Plot(corners: [
                        GeoPoint(latitude: -8.4095, longitude: 115.1889),
                        GeoPoint(latitude: -8.4095, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1889),
                    ])
                ]),
            Farm(
                name: "Carik Kaja",
                farmerName: "Ibu Made",
                plots: [
                    Plot(corners: [
                        GeoPoint(latitude: -8.4095, longitude: 115.1905),
                        GeoPoint(latitude: -8.4095, longitude: 115.1920),
                        GeoPoint(latitude: -8.4108, longitude: 115.1920),
                        GeoPoint(latitude: -8.4108, longitude: 115.1905),
                    ])
                ]),
        ],
        onOpen: { _ in }
    )
    .ignoresSafeArea()
}
