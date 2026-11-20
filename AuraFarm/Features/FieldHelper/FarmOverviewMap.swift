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
    /// Where the map is looking. Held outside, so searching can send it somewhere.
    @Binding var camera: MapCameraPosition
    /// Called with the plot the helper tapped, and the farm it belongs to.
    let onOpen: (Farm, Plot) -> Void

    var onDeselect: () -> Void
    /// Drawn thicker and brighter than the rest.
    var selected: Plot.ID?

    /// Lets the controls be placed by hand instead of where the system puts them.
    @Namespace private var mapScope

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, scope: mapScope) {
                // Where the helper is standing, since the map opens there.
                UserAnnotation()

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
                                    label(
                                        farm.title(of: plot), farm.name, in: colour,
                                        isSelected: plot.id == selected)
                                }
                                .buttonStyle(.plain)
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
            }
            .mapStyle(.imagery)
            // None where the system puts them: its trailing corner is where the navigation
            // bar's own button already is, and the two sat on top of each other.
            .mapControls {}
            // The way back to where the helper is standing, after they have panned off it,
            // above the search button at the other end of the screen.
            .overlay(alignment: .bottomTrailing) {
                MapUserLocationButton(scope: mapScope)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, 16)
                    .padding(.bottom, 108)
            }
            .onTapGesture { point in
                guard let coordinate = proxy.convert(point, from: .local),
                    let hit = plot(at: GeoPoint(coordinate))
                else {
                    onDeselect()
                    return
                }
                onOpen(hit.farm, hit.plot)
            }
            // What lets the button placed by hand above find this map.
            .mapScope(mapScope)
        }
    }

    /// Worked out against everyone on the phone, so two farmers never share a colour.
    private func colour(of farm: Farm) -> Color {
        FarmerColour.colour(for: farm.farmerName, among: farms.map(\.farmerName))
    }

    /// The plot's number over the farm's name, on its land. Big enough to tap, and in the farmer's colour so it
    /// reads as part of the shape under it rather than as a pin dropped on top.
    private func label(_ title: String, _ name: String, in colour: Color, isSelected: Bool)
        -> some View
    {
        let shape = RoundedRectangle(cornerRadius: 14)
        return VStack(spacing: 0) {
            Text(title).font(.caption2.weight(.medium))
            Text(name).font(.subheadline.weight(.semibold))
        }
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(minHeight: 32)
            .background(colour, in: shape)
            .overlay(shape.stroke(.white.opacity(0.9), lineWidth: 2))
            .shadow(radius: 2)
            .scaleEffect(isSelected ? 1.2 : 1)
            .animation(.snappy, value: isSelected)
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

    /// Every plot in view, which is where the map opens and where it goes back to when the
    /// land changes.
    static func fitting(_ farms: [Farm]) -> MapCameraPosition {
        guard let region = LandGeometry.region(fitting: farms.flatMap(\.allCorners)) else {
            return .automatic
        }
        return .region(region)
    }
}

#Preview {
    @Previewable @State var camera = MapCameraPosition.automatic
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
        camera: $camera,
        onOpen: { _, _ in }, onDeselect: {}
    )
    .ignoresSafeArea()
}
