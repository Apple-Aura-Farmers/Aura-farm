import AuraFarmKit
import SwiftData
import SwiftUI

/// Adds NPK results to a field, or edits them, typed in from a soil test kit or a lab report.
///
/// A kit gives a class per nutrient. A lab gives a value; in a unit with thresholds the class is
/// filled in from it, and in any other unit it is picked from what the lab report says.
struct NutrientTestEditorView: View {
    let field: Field
    /// nil to add new results.
    let test: NutrientTest?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var testedAt = Date.now
    @State private var source: NutrientSource = .soilTestKit
    @State private var sourceName = ""
    @State private var levels: [Nutrient: NutrientLevel] = [:]
    /// Typed as text so an empty box means "not entered" rather than zero.
    @State private var values: [Nutrient: String] = [:]
    @State private var units: [Nutrient: NutrientUnit] = [:]
    @State private var pHText = ""
    @State private var organicCarbonText = ""
    @State private var straw: StrawPractice = .unknown
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(test == nil ? "NPK Results for \(field.name)" : "Edit NPK Results")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                Section {
                    DatePicker("Tested on", selection: $testedAt, in: ...Date.now, displayedComponents: .date)
                    Picker("From", selection: $source) {
                        ForEach(NutrientSource.allCases, id: \.self) { source in
                            Text(source.label).tag(source)
                        }
                    }
                    TextField("Kit or lab", text: $sourceName, prompt: Text(sourceNamePrompt))
                }

                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    nutrientSection(nutrient)
                }

                Section {
                    TextField("pH", text: $pHText, prompt: Text("Optional, for example 6.2"))
                    TextField(
                        "Organic carbon (C-organik, %)",
                        text: $organicCarbonText,
                        prompt: Text("Optional, from a lab, for example 1.8")
                    )
                    Picker("Straw from the last harvest", selection: $straw) {
                        ForEach(StrawPractice.allCases, id: \.self) { practice in
                            Text(practice.label).tag(practice)
                        }
                    }
                } header: {
                    Text("Soil")
                } footer: {
                    if !pHText.isBlank && pH == nil {
                        Text("Enter a pH between 2.5 and 10.5.")
                            .foregroundStyle(.red)
                    } else if !organicCarbonText.isBlank && organicCarbon == nil {
                        Text("Enter organic carbon as a percentage between 0 and 60.")
                            .foregroundStyle(.red)
                    } else {
                        Text(
                            "Straw put back into the field lowers the KCl dose. Organic carbon below 2% "
                                + "adds organic matter to the plan."
                        )
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 480, idealHeight: 620)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(test == nil ? "Add Results" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 500)
        .onAppear(perform: load)
    }

    private func nutrientSection(_ nutrient: Nutrient) -> some View {
        Section {
            if source == .laboratory {
                HStack {
                    TextField("Value", text: valueBinding(nutrient), prompt: Text("Optional"))
                    Picker("Unit", selection: unitBinding(nutrient)) {
                        ForEach(NutrientUnit.units(for: nutrient), id: \.self) { unit in
                            Text(unit.label).tag(unit)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            Picker("Class", selection: levelBinding(nutrient)) {
                Text("Not tested").tag(NutrientLevel?.none)
                ForEach(NutrientLevel.allCases, id: \.self) { level in
                    Text(level.label).tag(NutrientLevel?.some(level))
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("\(nutrient.name) (\(nutrient.symbol))")
        } footer: {
            if let note = valueNote(for: nutrient) {
                Text(note)
                    .foregroundStyle(isValueInvalid(nutrient) ? Color.red : Color.secondary)
            }
        }
    }

    // MARK: - Bindings

    private func levelBinding(_ nutrient: Nutrient) -> Binding<NutrientLevel?> {
        Binding(
            get: { levels[nutrient] },
            set: { levels[nutrient] = $0 }
        )
    }

    private func valueBinding(_ nutrient: Nutrient) -> Binding<String> {
        Binding(
            get: { values[nutrient] ?? "" },
            set: { text in
                values[nutrient] = text
                fillLevelFromValue(of: nutrient)
            }
        )
    }

    private func unitBinding(_ nutrient: Nutrient) -> Binding<NutrientUnit> {
        Binding(
            get: { unit(of: nutrient) },
            set: { newUnit in
                units[nutrient] = newUnit
                fillLevelFromValue(of: nutrient)
            }
        )
    }

    // MARK: - Reading the form

    private var sourceNamePrompt: String {
        source == .soilTestKit ? "For example, PUTS" : "The lab's name"
    }

    private func unit(of nutrient: Nutrient) -> NutrientUnit {
        units[nutrient] ?? NutrientUnit.units(for: nutrient)[0]
    }

    /// The lab value, when one is entered and reads as a number of zero or more.
    private func value(of nutrient: Nutrient) -> Double? {
        guard source == .laboratory, let number = Self.number(from: values[nutrient] ?? ""), number >= 0
        else { return nil }
        return number
    }

    private func isValueInvalid(_ nutrient: Nutrient) -> Bool {
        source == .laboratory && !(values[nutrient] ?? "").isBlank && value(of: nutrient) == nil
    }

    private func valueNote(for nutrient: Nutrient) -> String? {
        guard source == .laboratory else { return nil }
        if isValueInvalid(nutrient) {
            return "Enter the value as a number, or leave it empty."
        }
        guard let value = value(of: nutrient) else { return nil }
        if let level = NutrientThresholds.level(of: value, in: unit(of: nutrient)) {
            return "\(level.label) for this value. Change the class if the lab report says otherwise."
        }
        return "Pick the class the lab report gives for this value."
    }

    /// pH, when one is entered and is a value a soil can have.
    private var pH: Double? {
        guard let number = Self.number(from: pHText), SoilAcidity.plausibleRange.contains(number) else {
            return nil
        }
        return number
    }

    /// Organic carbon, when one is entered and is a percentage a soil can have. Peat soils run
    /// high, so the ceiling is generous.
    private var organicCarbon: Double? {
        guard let number = Self.number(from: organicCarbonText), (0...60).contains(number) else {
            return nil
        }
        return number
    }

    private var hasAnyResult: Bool {
        !levels.isEmpty || pH != nil || organicCarbon != nil
    }

    private var canSave: Bool {
        hasAnyResult
            && (pHText.isBlank || pH != nil)
            && (organicCarbonText.isBlank || organicCarbon != nil)
            && !Nutrient.allCases.contains(where: isValueInvalid)
    }

    private func fillLevelFromValue(of nutrient: Nutrient) {
        guard let value = value(of: nutrient),
            let level = NutrientThresholds.level(of: value, in: unit(of: nutrient))
        else { return }
        levels[nutrient] = level
    }

    /// Accepts a decimal comma as well as a point.
    private static func number(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    // MARK: - Loading and saving

    private func load() {
        guard let test else { return }
        testedAt = test.testedAt
        source = test.source
        sourceName = test.sourceName
        straw = test.straw
        notes = test.notes
        pHText = test.pH.map { $0.formatted(.number) } ?? ""
        organicCarbonText = test.organicCarbonPercent.map { $0.formatted(.number) } ?? ""
        for nutrient in Nutrient.allCases {
            levels[nutrient] = test.level(of: nutrient)
            if let measurement = test.measurement(of: nutrient) {
                values[nutrient] = measurement.value.formatted(.number)
                units[nutrient] = measurement.unit
            }
        }
    }

    private func save() {
        let saved: NutrientTest
        if let test {
            saved = test
        } else {
            saved = NutrientTest(testedAt: testedAt, source: source)
            modelContext.insert(saved)
            saved.field = field
        }
        saved.testedAt = testedAt
        saved.source = source
        saved.sourceName = sourceName.trimmingCharacters(in: .whitespaces)
        saved.straw = straw
        saved.pH = pH
        saved.organicCarbonPercent = organicCarbon
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        for nutrient in Nutrient.allCases {
            saved.setLevel(levels[nutrient], of: nutrient)
            // A kit has no values, so switching a lab entry to a kit drops them.
            let measurement = value(of: nutrient).map { (value: $0, unit: unit(of: nutrient)) }
            saved.setMeasurement(measurement, of: nutrient)
        }
        try? modelContext.save()
        dismiss()
    }
}

extension String {
    /// True when there is nothing but whitespace.
    fileprivate var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
