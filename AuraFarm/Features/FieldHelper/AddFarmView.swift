//
//  AddFarmView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Adding a farm: the farmer's name and where their land is. Both are needed before it can be
/// saved, because a farm with no outline cannot be shown on the map.
struct AddFarmView: View {
    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var farmerName = ""
    @State private var corners: [GeoPoint] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Farmer") {
                    TextField("Farmer's name", text: $farmerName)
                        .textContentType(.name)
                }

                Section {
                    if hasUsableOutline {
                        LandMapView(corners: corners)
                            .frame(height: 180)
                            .listRowInsets(EdgeInsets())
                        LabeledContent("Area", value: areaText)
                    }
                    NavigationLink {
                        LandOutlineEditorView(corners: $corners)
                    } label: {
                        Label(
                            corners.isEmpty ? "Mark the land on the map" : "Edit the outline",
                            systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Land")
                } footer: {
                    if let landProblem {
                        Text(landProblem).foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Add a farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
        }
    }

    private var trimmedName: String {
        farmerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Three corners that do not cross themselves, so the area means something.
    private var hasUsableOutline: Bool {
        corners.count >= 3 && !LandGeometry.crossesItself(corners)
    }

    private var canSave: Bool { !trimmedName.isEmpty && hasUsableOutline }

    private var areaText: String {
        LandGeometry.areaDescription(squareMetres: LandGeometry.areaSquareMetres(of: corners) ?? 0)
    }

    /// What is wrong with the outline so far, once the helper has started on it.
    private var landProblem: String? {
        if corners.isEmpty { return nil }
        if corners.count < 3 { return "The land needs at least 3 corners." }
        if LandGeometry.crossesItself(corners) {
            return "The edges of the outline cross each other. Open it and fix the dots."
        }
        return nil
    }

    private func save() {
        store.add(Farm(farmerName: trimmedName, corners: corners))
        dismiss()
    }
}

#Preview {
    AddFarmView()
        .environment(FarmStore(fileURL: nil))
}
