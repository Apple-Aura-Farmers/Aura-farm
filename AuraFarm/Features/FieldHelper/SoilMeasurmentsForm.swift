//
//  SoilMeasurmentsForm.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 10/11/26.
//

import SwiftUI

/// Where a field helper records what they know about a farm's soil: NPK, pH, organic carbon and
/// any fertilizer put on. Every field is optional; leave blank what is not known, and empty a
/// field to remove a value that was entered before.
struct SoilMeasurementsForm: View {
    let farm: Farm

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var nitrogen: Double?
    @State private var phosphorus: Double?
    @State private var potassium: Double?
    @State private var ph: Double?
    @State private var organicCarbon: Double?
    @State private var fertilizerProduct: String
    @State private var fertilizerAmount: Double?

    init(farm: Farm) {
        self.farm = farm
        let soil = farm.soil
        _nitrogen = State(initialValue: soil?.nitrogen)
        _phosphorus = State(initialValue: soil?.phosphorus)
        _potassium = State(initialValue: soil?.potassium)
        _ph = State(initialValue: soil?.ph)
        _organicCarbon = State(initialValue: soil?.organicCarbonPercent)
        _fertilizerProduct = State(initialValue: soil?.fertilizerProduct ?? "")
        _fertilizerAmount = State(initialValue: soil?.fertilizerKilogramsPerHectare)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    numberRow("Nitrogen (N)", value: $nitrogen, unit: "mg/kg")
                    numberRow("Phosphorus (P)", value: $phosphorus, unit: "mg/kg")
                    numberRow("Potassium (K)", value: $potassium, unit: "mg/kg")
                } header: {
                    Text("NPK")
                } footer: {
                    Text(
                        "Milligrams per kilogram of soil, as the probe or lab report gives them. "
                            + "Standard: N \(SoilStandards.nitrogen.description), "
                            + "P \(SoilStandards.phosphorus.description), "
                            + "K \(SoilStandards.potassium.description)."
                    )
                }

                Section {
                    numberRow("pH", value: $ph, unit: "0 to 14")
                } header: {
                    Text("Acidity")
                } footer: {
                    Text("Standard: \(SoilStandards.ph.description).")
                }

                Section {
                    numberRow("Soil organic carbon", value: $organicCarbon, unit: "%")
                } header: {
                    Text("Organic carbon")
                } footer: {
                    Text("Standard: \(SoilStandards.organicCarbon.description), as a percentage.")
                }

                Section {
                    TextField("Product, such as urea or compost", text: $fertilizerProduct)
                        .textInputAutocapitalization(.sentences)
                    numberRow("Amount", value: $fertilizerAmount, unit: "kg/ha")
                } header: {
                    Text("Fertilizer")
                } footer: {
                    Text("What has been put on this land, and how much per hectare.")
                }

                if !measurements.problems.isEmpty {
                    Section {
                        ForEach(measurements.problems, id: \.self) { problem in
                            Label(problem, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Soil measurements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!measurements.problems.isEmpty)
                }
            }
        }
    }

    /// One optional number: a label, a box that takes a decimal, and its unit.
    private func numberRow(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("Optional", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 110)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 52, alignment: .leading)
        }
    }

    /// What the form holds right now.
    private var measurements: SoilMeasurements {
        let product = fertilizerProduct.trimmingCharacters(in: .whitespacesAndNewlines)
        return SoilMeasurements(
            nitrogen: nitrogen, phosphorus: phosphorus, potassium: potassium, ph: ph,
            organicCarbonPercent: organicCarbon,
            fertilizerProduct: product.isEmpty ? nil : product,
            fertilizerKilogramsPerHectare: fertilizerAmount)
    }

    private func save() {
        // Read the farm afresh, in case it changed while this form was open.
        guard var current = store.farms.first(where: { $0.id == farm.id }) else {
            dismiss()
            return
        }
        var saved = measurements
        saved.updatedAt = Date()
        current.soil = saved.isEmpty ? nil : saved
        store.update(current)
        dismiss()
    }
}

#Preview {
    SoilMeasurementsForm(
        farm: Farm(
            farmerName: "Pak Wayan",
            corners: [
                GeoPoint(latitude: -8.4095, longitude: 115.1889),
                GeoPoint(latitude: -8.4095, longitude: 115.1900),
                GeoPoint(latitude: -8.4105, longitude: 115.1896),
            ])
    )
    .environment(FarmStore(fileURL: nil))
}
