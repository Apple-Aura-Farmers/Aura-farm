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
    let farm: Farm

    var body: some View {
        List {
            Section {
                LandMapView(corners: farm.corners, isInteractive: true)
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
        .navigationTitle(farm.farmerName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        FarmDetailView(
            farm: Farm(
                farmerName: "Pak Wayan",
                corners: [
                    GeoPoint(latitude: -8.4095, longitude: 115.1889),
                    GeoPoint(latitude: -8.4095, longitude: 115.1900),
                    GeoPoint(latitude: -8.4105, longitude: 115.1900),
                    GeoPoint(latitude: -8.4105, longitude: 115.1889),
                ]))
    }
}
