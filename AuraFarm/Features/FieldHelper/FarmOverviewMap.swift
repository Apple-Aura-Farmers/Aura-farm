//
//  FarmOverviewMap.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import MapKit
import SwiftUI

/// Every plot the helper looks after on one satellite map.
///
/// A plot is drawn in its farmer's colour and carries its number, so whose land it is and
/// which of their plots it is can both be read without opening anything. Plain imagery with
/// no road or place labels, so the land is the only thing drawn on it.
struct FarmsOverviewMap: View {
    let farms: [Farm]
    /// Called with the plot the helper tapped, and the farm it belongs to.
    let onOpen: (Farm, Plot) -> Void
    /// Drawn thicker and brighter than the rest.
    var selected: Plot.ID?

    var body: some View {
        MapReader { proxy in
            Map(initialPosition: initialPosition) {
                ForEach(farms) { farm in
                    ForEach(farm.plots) { plot in
                        let colour = colour(of: farm)
                        MapPolygon(coordinates: plot.corners.map(\.coordinate))
                            .foregroundStyle(colour.opacity(plot.id == selected ? 0.45 : 0.3))
                            .stroke(colour, lineWidth: plot.id == selected ? 3 : 2)
                        if let middle = LandGeometry.centre(of: plot.corners) {
                            Annotation(
                                farm.title(of: plot), coordinate: middle.coordinate,
                                anchor: .center
                            ) {
                                Button {
                                    onOpen(farm, plot)
                                } label: {
                                    number(farm.number(of: plot), in: colour)
                                }
                                .buttonStyle(.plain)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
            }
            .mapStyle(.imagery)
            .mapControls {
                MapCompass()
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local),
                    let hit = plot(at: GeoPoint(coordinate))
                else { return }
                onOpen(hit.farm, hit.plot)
            }
        }
    }

    /// Worked out against everyone on the phone, so two farmers never share a colour.
    private func colour(of farm: Farm) -> Color {
        FarmerColour.colour(for: farm.farmerName, among: farms.map(\.farmerName))
    }

    /// The plot's number on its own land. Big enough to tap, and in the farmer's colour so it
    /// reads as part of the shape under it rather than as a pin dropped on top.
    private func number(_ value: Int, in colour: Color) -> some View {
        Text(value, format: .number)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(colour, in: Circle())
            .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 2))
            .shadow(radius: 2)
    }

    /// The plot containing the spot. Where plots overlap, the smaller one wins, so a small
    /// plot inside a big one can still be reached.
    private func plot(at spot: GeoPoint) -> (farm: Farm, plot: Plot)? {
        farms
            .flatMap { farm in
                farm.plots
                    .filter { LandGeometry.contains(spot, in: $0.corners) }
                    .map { (farm: farm, plot: $0, area: $0.areaSquareMetres ?? 0) }
            }
            .min { $0.area < $1.area }
            .map { ($0.farm, $0.plot) }
    }

    /// Opens with every plot in view.
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
                    Plot(
                        name: "Tabanan",
                        corners: [
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
                    Plot(
                        name: "Panjer",
                        corners: [
                            GeoPoint(latitude: -8.4095, longitude: 115.1905),
                            GeoPoint(latitude: -8.4095, longitude: 115.1920),
                            GeoPoint(latitude: -8.4108, longitude: 115.1920),
                            GeoPoint(latitude: -8.4108, longitude: 115.1905),
                        ])
                ]),
        ],
        onOpen: { _, _ in }
    )
    .ignoresSafeArea()
}
