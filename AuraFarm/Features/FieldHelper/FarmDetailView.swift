//
//  FarmDetailView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// One farm: the land on the map, and what is known about the soil.
///
/// PLACEHOLDER: the NPK and lab result sections are empty for now. NPK has no source yet, and
/// lab results come from the Microscope Operator side, which does not know which farm a
/// sample belongs to.
struct FarmDetailView: View {
    /// Looked up in the store each time, so the page shows changes made by Edit straight away.
    let farmID: UUID

    @Environment(FarmStore.self) private var store
    @State private var showEdit = false

    private var farm: Farm? { store.farms.first { $0.id == farmID } }

    var body: some View {
        Group {
            if let farm {
                details(for: farm)
                    .navigationTitle(farm.farmerName)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Edit") { showEdit = true }
                        }
                    }
                    .sheet(isPresented: $showEdit) {
                        FarmFormView(editing: farm)
                    }
            } else {
                ContentUnavailableView("This farm is no longer here", systemImage: "leaf")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    private func details(for farm: Farm) -> some View {
        List {
            Section {
                LandMapView(corners: farm.corners, isInteractive: true)
                    .id(farm.corners)
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
            }

            Section("Land") {
                if let area = farm.areaSquareMetres {
                    LabeledContent(
                        "Area", value: LandGeometry.areaDescription(squareMetres: area))
                }
                LabeledContent("Corners", value: "\(farm.corners.count)")
                LabeledContent("Added") {
                    Text(farm.createdAt, format: .dateTime.day().month().year())
                }
            }

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
        }
    }
}

#Preview {
    let farm = Farm(
        farmerName: "Pak Wayan",
        corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1889),
        ])
    NavigationStack {
        FarmDetailView(farmID: farm.id)
    }
    .environment(FarmStore(fileURL: nil, farms: [farm]))
}
