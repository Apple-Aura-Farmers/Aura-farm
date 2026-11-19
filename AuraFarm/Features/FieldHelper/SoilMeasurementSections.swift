import SwiftUI

/// The measurement form's sections: the day, NPK, acidity, organic carbon and fertilizer. The
/// editor and the plot's page both show these, so what a helper sees on the page is what they
/// edit. With `isEditable` off nothing can be changed, the numbers read as plain text, and
/// anything left blank is left out rather than shown empty.
struct SoilMeasurementSections: View {
    @Binding var draft: SoilMeasurements
    let isEditable: Bool
    /// The microscope test from the day of this measurement, shown under the date when read-only.
    var biodiversity: FarmTest? = nil

    var body: some View {
        Group {
            date
            if !isEditable, let biodiversity {
                Section("Biodiversity") {
                    NavigationLink {
                        SoilResultScreen(sweep: biodiversity.sweep)
                    } label: {
                        BiodiversityRow(test: biodiversity)
                    }
                }
            }
            npk
            acidity
            organicCarbon
            fertilizer
        }
    }

    var date: some View {
        Section {
            if isEditable {
                DatePicker(
                    "Measured on", selection: $draft.measuredAt, in: ...Date.now,
                    displayedComponents: .date)
            } else {
                LabeledContent(
                    "Last measured on", value: draft.measuredAt.formatted(date: .abbreviated, time: .omitted))
            }
        }
    }

    @ViewBuilder
    var npk: some View {
        if isEditable || draft.npkHealth != nil {
            Section {
                NutrientBar(health: draft.npkHealth)
                    .listRowSeparator(.hidden)
                if isEditable || draft.nitrogen != nil {
                    numberRow("Nitrogen (N)", value: $draft.nitrogen, unit: "mg/kg")
                }
                if isEditable || draft.phosphorus != nil {
                    numberRow("Phosphorous (P)", value: $draft.phosphorus, unit: "mg/kg")
                }
                if isEditable || draft.potassium != nil {
                    numberRow("Potassium (K)", value: $draft.potassium, unit: "mg/kg")
                }
            } header: {
                Text("NPK")
            } footer: {
                Text(
                    "Milligrams per kilogram of soil. Standard: N \(SoilStandards.nitrogen.description), "
                        + "P \(SoilStandards.phosphorus.description), "
                        + "K \(SoilStandards.potassium.description). The standards are placeholders "
                        + "and have not been checked by an agronomist."
                )
            }
        }
    }

    @ViewBuilder
    var acidity: some View {
        if isEditable || draft.ph != nil {
            Section {
                VStack(spacing: 6) {
                    Slider(
                        value: Binding(get: { draft.ph ?? 7 }, set: { draft.ph = $0 }),
                        in: 0...14, step: 0.1
                    )
                    .accessibilityLabel("Acidity")
                    .accessibilityValue(reading(draft.ph))
                    .disabled(!isEditable)
                    HStack {
                        Text("acidic")
                        Spacer()
                        Text("neutral")
                        Spacer()
                        Text("alkaline")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                LabeledContent("pH", value: reading(draft.ph))
                if isEditable, draft.ph != nil {
                    Button("Clear", role: .destructive) { draft.ph = nil }
                }
                if isEditable {
                    Picker("Field at the time", selection: $draft.phFieldWater) {
                        Text("Not recorded").tag(PHFieldWater?.none)
                        ForEach(PHFieldWater.allCases) { Text($0.label).tag(PHFieldWater?.some($0)) }
                    }
                } else if let water = draft.phFieldWater {
                    LabeledContent("Field at the time", value: water.label)
                }
            } header: {
                Text("Acidity (pH)")
            } footer: {
                Text(
                    "Provisional target for flooded rice: about pH \(SoilStandards.ph.description). "
                        + "Flooding often moves pH toward neutral, so a reading from dry soil may "
                        + "differ from the pH around the roots once the field is flooded."
                )
            }
        }
    }

    @ViewBuilder
    var organicCarbon: some View {
        if isEditable || draft.organicCarbonPercent != nil {
            Section {
                numberRow("SOC", value: $draft.organicCarbonPercent, unit: "%")
            } header: {
                Text("Soil Organic Carbon")
            } footer: {
                Text("Standard: \(SoilStandards.organicCarbon.description) percent by weight.")
            }
        }
    }

    @ViewBuilder
    var fertilizer: some View {
        if isEditable || draft.fertilizerType != nil || draft.fertilizerProduct != nil
            || draft.fertilizerKilogramsPerHectare != nil
        {
            Section {
                // Picked from a short list, not typed, so the same answer always reads the same.
                if isEditable {
                    Picker("Type", selection: $draft.fertilizerType) {
                        Text("Choose…").tag(FertilizerType?.none)
                        ForEach(FertilizerType.allCases) { Text($0.label).tag(FertilizerType?.some($0)) }
                    }
                } else if let type = draft.fertilizerType {
                    LabeledContent("Type", value: type.label)
                }
                if let fertilizerType = draft.fertilizerType {
                    Text(fertilizerType.definition)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if isEditable {
                    TextField(
                        "Product name (optional)",
                        text: Binding(
                            get: { draft.fertilizerProduct ?? "" },
                            set: { draft.fertilizerProduct = $0.isEmpty ? nil : $0 })
                    )
                    .textInputAutocapitalization(.sentences)
                } else if let product = draft.fertilizerProduct {
                    LabeledContent("Product", value: product)
                }
                if isEditable || draft.fertilizerKilogramsPerHectare != nil {
                    numberRow("Amount", value: $draft.fertilizerKilogramsPerHectare, unit: "kg/ha")
                }
            } header: {
                Text("Fertilizer")
            } footer: {
                Text("What has been put on this land, and how much per hectare.")
            }
        }
    }

    // MARK: Pieces

    /// One optional number: a label, a box that takes a decimal, and its unit.
    func numberRow(_ label: String, value: Binding<Double?>, unit: String) -> some View {
        LabeledContent(label) {
            if isEditable {
                HStack(spacing: 6) {
                    TextField("—", value: value, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110)
                    Text(unit)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(value.wrappedValue.map { "\($0.formatted(.number)) \(unit)" } ?? "—")
            }
        }
    }

    func reading(_ value: Double?) -> String {
        guard let value else { return "Not recorded" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
