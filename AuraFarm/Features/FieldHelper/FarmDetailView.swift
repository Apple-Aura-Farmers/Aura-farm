//
//  FarmDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// One farm: its plots on the map, and what is known about the soil.
///
/// PLACEHOLDER: the NPK and lab result sections are empty for now. NPK has no source yet, and
/// lab results come from the Microscope Operator side, which does not know which farm a
/// sample belongs to.
struct FarmDetailView: View {
    /// Looked up in the store each time, so the page shows changes made by Edit straight away.
    let farmID: UUID

    @Environment(FarmStore.self) private var store
    @State private var showEdit = false
    /// The plot waiting on a yes to being deleted.
    @State private var plotToDelete: Plot?

    private var farm: Farm? { store.farms.first { $0.id == farmID } }

    var body: some View {
        Group {
            if let farm {
                details(for: farm)
                    .navigationTitle(farm.name)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit") { showEdit = true }
                        }
                    }
                    .sheet(isPresented: $showEdit) {
                        FarmFormView(editing: farm)
                    }
                    .confirmationDialog(
                        "Delete this plot?",
                        isPresented: Binding(
                            get: { plotToDelete != nil },
                            set: { if !$0 { plotToDelete = nil } }),
                        presenting: plotToDelete
                    ) { plot in
                        Button("Delete plot \(farm.number(of: plot))", role: .destructive) {
                            Task { await remove(plot, from: farm) }
                        }
                    } message: { _ in
                        Text(
                            "The plot's outline will be removed from this phone and the "
                                + "records."
                        )
                    }
            } else {
                ContentUnavailableView("This farm is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(for farm: Farm) -> some View {
        List {
            if !farm.allCorners.isEmpty {
                Section {
                    LandMapView(outlines: farm.plots.map(\.corners), isInteractive: true)
                        .id(farm.allCorners)
                        .frame(height: 260)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Farm") {
                LabeledContent("Farmer", value: farm.farmerName)
                if let area = farm.areaSquareMetres {
                    LabeledContent(
                        "Total area", value: LandGeometry.areaDescription(squareMetres: area))
                }
                LabeledContent("Added") {
                    Text(farm.createdAt, format: .dateTime.day().month().year())
                }
            }

            plots(of: farm)

            Section {
                Text("No reading yet.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Soil nutrients (NPK)")
            }

            Section {
                Text("No lab results yet.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Lab results")
            } footer: {
                Text("Results from the microscope operator will show here.")
            }

            Section {
                PublishButton(title: "Publish farm") {
                    guard let uploader = FarmUploader() else {
                        throw FarmUploader.Failure.notConfigured
                    }
                    try await uploader.upload(farm)
                }
            } footer: {
                Text(
                    "A sample can only be filed against land the records already know, so "
                        + "publish the farm before taking one from it."
                )
            }
        }
    }

    private func plots(of farm: Farm) -> some View {
        Section {
            ForEach(farm.plots) { plot in
                NavigationLink {
                    LandOutlineEditorView(
                        corners: plot.corners,
                        neighbours: store.farms.neighbours(excluding: plot.id)
                    ) { corners in
                        replace(plot, with: corners, in: farm)
                    }
                } label: {
                    row(for: plot, in: farm)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        plotToDelete = plot
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }

            NavigationLink {
                LandOutlineEditorView(
                    corners: [], neighbours: store.farms.neighbours()
                ) { corners in
                    add(corners, to: farm)
                }
            } label: {
                Label("Add a plot", systemImage: "plus")
            }
        } header: {
            Text("Plots")
        } footer: {
            if farm.plots.isEmpty {
                Text("Mark each piece of this farmer's land as its own plot.")
            }
        }
    }

    private func row(for plot: Plot, in farm: Farm) -> some View {
        HStack(spacing: 14) {
            FarmOutlineThumbnail(corners: plot.corners)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plot \(farm.number(of: plot))")
                    .font(.headline)
                if let area = plot.areaSquareMetres {
                    Text(LandGeometry.areaDescription(squareMetres: area))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Changing the plots

    private func add(_ corners: [GeoPoint], to farm: Farm) {
        var changed = farm
        changed.plots.append(Plot(corners: corners))
        store.update(changed)
    }

    private func replace(_ plot: Plot, with corners: [GeoPoint], in farm: Farm) {
        guard let index = farm.plots.firstIndex(where: { $0.id == plot.id }) else { return }
        var changed = farm
        changed.plots[index].corners = corners
        store.update(changed)
    }

    /// Takes the plot out of the records first, so one deleted here but left there does not
    /// come back with the next pull.
    private func remove(_ plot: Plot, from farm: Farm) async {
        if let uploader = FarmUploader() {
            do {
                try await uploader.delete(plot)
            } catch {
                store.report(error.localizedDescription)
                return
            }
        }
        var changed = farm
        changed.plots.removeAll { $0.id == plot.id }
        store.update(changed)
    }
}

#Preview {
    let farm = Farm(
        name: "Subak Jatiluwih",
        farmerName: "Pak Wayan",
        plots: [
            Plot(corners: [
                GeoPoint(latitude: -8.4095, longitude: 115.1889),
                GeoPoint(latitude: -8.4095, longitude: 115.1900),
                GeoPoint(latitude: -8.4105, longitude: 115.1900),
                GeoPoint(latitude: -8.4105, longitude: 115.1889),
            ])
        ])
    NavigationStack {
        FarmDetailView(farmID: farm.id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
