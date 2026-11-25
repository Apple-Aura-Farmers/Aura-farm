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
    /// Offers "No farm" first, for the operator's own sample.
    var allowsNoFarm = false

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    /// A plot was chosen on the plot list. This list closes itself once that one has gone, so
    /// the two never pop together.
    @State private var chosen = false

    var body: some View {
        List {
            if allowsNoFarm {
                Button {
                    details.useNoFarm()
                    dismiss()
                } label: {
                    HStack {
                        Text("No farm").font(.headline)
                        Spacer()
                        if details.farmID == nil {
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
            ForEach(matching) { farm in
                // A farm with several plots asks which one the soil came from.
                if farm.plots.count > 1 {
                    NavigationLink {
                        PlotChoiceList(farm: farm, details: $details) { chosen = true }
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
        }
        .searchable(text: $search, prompt: "Search farms")
        .overlay {
            if store.farms.isEmpty && !allowsNoFarm {
                ContentUnavailableView(
                    "No farms yet",
                    systemImage: "leaf",
                    description: Text(
                        "Farms are added on the Field Helper side. Once one has been added, it shows up here."
                    )
                )
            } else if !search.isEmpty && matching.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .navigationTitle("Choose a farm")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if chosen { dismiss() } }
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

/// The plots of one farm, to choose which one the soil came from.
private struct PlotChoiceList: View {
    let farm: Farm
    @Binding var details: SampleDetails
    var chosen: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(farm.plots) { plot in
            Button {
                details.use(plot, of: farm)
                chosen()
                dismiss()
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
