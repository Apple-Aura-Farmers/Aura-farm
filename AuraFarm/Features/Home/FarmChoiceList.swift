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
                    description: Text("Farms are added on the Field Helper side. Once one has been added, it shows up here.")
                )
            } else {
                List(matching) { farm in
                    Button {
                        details.use(farm)
                        dismiss()
                    } label: {
                        row(for: farm)
                    }
                    .buttonStyle(.plain)
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
            .filter { search.isEmpty || $0.farmerName.localizedStandardContains(search) }
            .sorted { $0.farmerName.localizedStandardCompare($1.farmerName) == .orderedAscending }
    }

    private func row(for farm: Farm) -> some View {
        HStack(spacing: 14) {
            FarmOutlineThumbnail(corners: farm.corners)
            VStack(alignment: .leading, spacing: 2) {
                Text(farm.farmerName)
                    .font(.headline)
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
                    farmerName: "Pak Wayan",
                    corners: [
                        GeoPoint(latitude: -8.4095, longitude: 115.1889),
                        GeoPoint(latitude: -8.4095, longitude: 115.1900),
                        GeoPoint(latitude: -8.4105, longitude: 115.1896),
                    ])
            ]))
}
