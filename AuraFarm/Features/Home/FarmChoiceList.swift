//
//  FarmChoiceList.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import SwiftUI

/// The farms the field helpers have added, to choose which one a sample came from. Picking one
/// fills in the sample's name, location and plot, so none of them are typed.
struct FarmChoiceList: View {
    @Binding var details: SampleDetails

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        Group {
            if store.farms.isEmpty {
                ContentUnavailableView(
                    "No farms yet",
                    systemImage: "leaf",
                    description: Text(
                        "Farms are added on the Field Helper side. Once one has been added, it shows up here."
                    )
                )
            } else {
                List(matching) { farm in
                    // A farm with several plots asks which one the soil came from.
                    if farm.plots.count > 1 {
                        NavigationLink {
                            plotList(for: farm)
                        } label: {
                            row(for: farm)
                        }
                    } else {
                        Button {
                            choose(farm.plots.first, of: farm)
                        } label: {
                            row(for: farm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .searchable(text: $search, prompt: "Search farms")
                .overlay {
                    if matching.isEmpty { ContentUnavailableView.search(text: search) }
                }
            }
        }
        .navigationTitle("Choose a farm")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var matching: [Farm] {
        store.farms
            .filter {
                search.isEmpty
                    || $0.name.localizedStandardContains(search)
                    || $0.farmerName.localizedStandardContains(search)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A farm with no plot yet has no land to take a location from, so it is chosen without one.
    private func choose(_ plot: Plot?, of farm: Farm) {
        details.use(plot, of: farm)
        dismiss()
    }

    private func plotList(for farm: Farm) -> some View {
        List(farm.plots) { plot in
            Button {
                choose(plot, of: farm)
            } label: {
                HStack(spacing: 14) {
                    FarmOutlineThumbnail(corners: plot.corners)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(farm.title(of: plot))
                            .font(.headline)
                        if !plot.name.isEmpty {
                            Text(plot.name)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if details.plotID == plot.id {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityLabel("Chosen")
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Choose a plot")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for farm: Farm) -> some View {
        HStack(spacing: 14) {
            // The first plot stands for the farm, the way the farm list draws it.
            FarmOutlineThumbnail(corners: farm.plots.first?.corners ?? [])
            VStack(alignment: .leading, spacing: 2) {
                Text(farm.name)
                    .font(.headline)
                Text(farm.farmerName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let area = farm.areaSquareMetres {
                    Text(LandGeometry.hectaresDescription(squareMetres: area))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if details.farmID == farm.id {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Chosen")
            }
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    NavigationStack {
        FarmChoiceList(details: .constant(.blank))
    }
    .environment(
        FarmStore(
            fileURL: nil,
            farms: [
                Farm(
                    name: "Subak Jatiluwih",
                    farmerName: "Pak Wayan",
                    plots: [
                        Plot(corners: [
                            GeoPoint(latitude: -8.4095, longitude: 115.1889),
                            GeoPoint(latitude: -8.4095, longitude: 115.1900),
                            GeoPoint(latitude: -8.4105, longitude: 115.1896),
                        ])
                    ])
            ]))
}
