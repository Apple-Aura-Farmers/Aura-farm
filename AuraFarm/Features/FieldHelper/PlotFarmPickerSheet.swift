import SwiftUI

/// Whose land the helper just marked. Shown after the outline is confirmed from the home map,
/// so a plot can be walked first and filed afterwards: either onto a farm already saved, or
/// onto a new one named here.
struct PlotFarmPickerSheet: View {
    let plot: Plot

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isNamingNewFarm = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LandMapView(corners: plot.corners)
                        .frame(height: 170)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    if let area = plot.areaSquareMetres {
                        Text(LandGeometry.areaDescription(squareMetres: area))
                    }
                }

                Section {
                    ForEach(sortedFarms) { farm in
                        Button {
                            add(to: farm)
                        } label: {
                            row(for: farm)
                        }
                    }
                    Button {
                        isNamingNewFarm = true
                    } label: {
                        Label("New farm", systemImage: "plus")
                    }
                } header: {
                    Text("Add this plot to")
                } footer: {
                    if store.farms.isEmpty {
                        Text("There are no farms yet, so this plot starts a new one.")
                    }
                }
            }
            .navigationTitle("Whose land is this?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") { dismiss() }
                }
            }
            .sheet(isPresented: $isNamingNewFarm) {
                // Closing this sheet too, once the farm is saved, so the helper lands back on
                // the map rather than on a picker for a plot already filed.
                FarmFormView(firstPlot: plot) { dismiss() }
            }
        }
    }

    private func row(for farm: Farm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(farm.name)
            Text(farm.farmerName)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sortedFarms: [Farm] {
        store.farms.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func add(to farm: Farm) {
        var changed = farm
        changed.plots.append(plot)
        store.update(changed)
        dismiss()
    }
}

#Preview {
    PlotFarmPickerSheet(
        plot: Plot(corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1900),
        ])
    )
    .environment(
        FarmStore(
            fileURL: nil,
            farms: [Farm(name: "Subak Jatiluwih", farmerName: "Pak Wayan")]))
}
