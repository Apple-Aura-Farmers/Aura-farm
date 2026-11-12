//
//  FarmFormView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// Adding a farm, or renaming one that is already saved: what the farm is called and whose it
/// is. The land is not asked for here, because a farm can have several plots; they are marked
/// one at a time on the farm's own page.
struct FarmFormView: View {
    /// The farm being changed, or nil when adding a new one.
    private let editing: Farm?
    /// Land marked before the farm existed, which becomes the new farm's first plot.
    private let firstPlot: Plot?
    /// Called once the farm has been saved, so a caller that opened this on top of its own
    /// sheet can close that too.
    private let onSave: (() -> Void)?

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var farmerName: String

    init(editing farm: Farm? = nil, firstPlot: Plot? = nil, onSave: (() -> Void)? = nil) {
        editing = farm
        self.firstPlot = firstPlot
        self.onSave = onSave
        _name = State(initialValue: farm?.name ?? "")
        _farmerName = State(initialValue: farm?.farmerName ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Farm") {
                    TextField("Farm name", text: $name)
                }

                Section {
                    TextField("Farmer's name", text: $farmerName)
                        .textContentType(.name)
                } header: {
                    Text("Farmer")
                } footer: {
                    if let firstPlot, let area = firstPlot.areaSquareMetres {
                        Text(
                            "The land you marked, "
                                + LandGeometry.areaDescription(squareMetres: area)
                                + ", becomes this farm's first plot."
                        )
                    } else if editing == nil {
                        Text("Mark the plots on the farm's page once it is saved.")
                    }
                }
            }
            .textInputAutocapitalization(.words)
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
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedFarmerName: String {
        farmerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedName.isEmpty && !trimmedFarmerName.isEmpty }

    private func save() {
        if var farm = editing {
            farm.name = trimmedName
            farm.farmerName = trimmedFarmerName
            store.update(farm)
        } else {
            store.add(
                Farm(
                    name: trimmedName,
                    farmerName: trimmedFarmerName,
                    plots: firstPlot.map { [$0] } ?? []
                ))
        }
        dismiss()
        onSave?()
    }
}

#Preview {
    FarmFormView()
        .environment(FarmStore(fileURL: nil))
}
