//
//  FarmFormView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Adding a farm, or changing one that is already saved: the farmer's name and where their land
/// is. Both are needed before it can be saved, because a farm with no outline cannot be shown
/// on the map.
struct FarmFormView: View {
    /// The farm being changed, or nil when adding a new one.
    private let editing: Farm?

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var farmerName: String
    @State private var corners: [GeoPoint]

    init(editing farm: Farm? = nil) {
        editing = farm
        _farmerName = State(initialValue: farm?.farmerName ?? "")
        _corners = State(initialValue: farm?.corners ?? [])
    }

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
                        LandOutlineEditorView(
                            corners: corners, neighbours: otherFarms
                        ) { confirmed in
                            corners = confirmed
                        }
                    } label: {
                        Label(
                            corners.isEmpty ? "Mark the land on the map" : "Edit the outline",
                            systemImage: "mappin.and.ellipse")
                    }
                } header: {
                    Text("Land")
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if let landProblem {
                            Text(landProblem).foregroundStyle(.orange)
                        }
                        if let overlapNote {
                            Text(overlapNote).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle(editing == nil ? "Add a farm" : "Edit farm")
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

    /// Every saved farm except the one being edited, which cannot overlap itself.
    private var otherFarms: [Farm] {
        store.farms.filter { $0.id != editing?.id }
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

    /// A reminder, not a block: the helper may have confirmed an overlap on purpose.
    private var overlapNote: String? {
        guard hasUsableOutline else { return nil }
        let overlapping = otherFarms.filter { LandGeometry.overlap(corners, $0.corners) }
        guard !overlapping.isEmpty else { return nil }
        let names = overlapping.map(\.farmerName).formatted(.list(type: .and))
        return "This outline overlaps \(names)'s land."
    }

    private func save() {
        if var farm = editing {
            farm.farmerName = trimmedName
            farm.corners = corners
            store.update(farm)
        } else {
            store.add(Farm(farmerName: trimmedName, corners: corners))
        }
        dismiss()
    }
}

#Preview {
    FarmFormView()
        .environment(FarmStore(fileURL: nil))
}
