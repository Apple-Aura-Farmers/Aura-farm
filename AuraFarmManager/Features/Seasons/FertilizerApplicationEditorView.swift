import AuraFarmKit
import SwiftData
import SwiftUI

/// Records fertilizer or organic matter put on a field during a season, or edits a record.
struct FertilizerApplicationEditorView: View {
    let season: Season
    /// nil to add a new record.
    let application: FertilizerApplication?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var appliedOn = Date.now
    @State private var product: AppliedProduct = .urea
    @State private var productName = ""
    /// Typed as text so an empty box means "not entered" rather than zero.
    @State private var kilogramsText = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(application == nil ? "Fertilizer Put On" : "Edit Fertilizer")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                DatePicker("Put on", selection: $appliedOn, in: ...Date.now, displayedComponents: .date)
                Picker("Product", selection: $product) {
                    ForEach(AppliedProduct.allCases, id: \.self) { product in
                        Text(product.label).tag(product)
                    }
                }
                if product.plannedFertilizer == nil {
                    TextField(
                        "Name",
                        text: $productName,
                        prompt: Text("Optional, for example Phonska 15-15-15")
                    )
                }
                TextField("Amount for the field (kg)", text: $kilogramsText, prompt: Text("For example, 50"))
                if let perHectare {
                    LabeledContent("Per hectare") {
                        Text("\(perHectare, format: .number.precision(.fractionLength(0...1))) kg")
                            .monospacedDigit()
                    }
                }
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(1...4)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(application == nil ? "Add" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(kilograms == nil)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 440)
        .onAppear(perform: load)
    }

    /// The amount, when entered as a number above zero.
    private var kilograms: Double? {
        let text = kilogramsText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard let number = Double(text), number > 0 else { return nil }
        return number
    }

    private var perHectare: Double? {
        guard let kilograms, let area = season.field?.areaHectares, area > 0 else { return nil }
        return kilograms / area
    }

    private func load() {
        guard let application else { return }
        appliedOn = application.appliedOn
        product = application.product
        productName = application.productName
        kilogramsText = application.kilograms.formatted(.number)
        notes = application.notes
    }

    private func save() {
        guard let kilograms else { return }
        let saved: FertilizerApplication
        if let application {
            saved = application
        } else {
            saved = FertilizerApplication(appliedOn: appliedOn, product: product, kilograms: kilograms)
            modelContext.insert(saved)
            saved.season = season
        }
        saved.appliedOn = appliedOn
        saved.product = product
        // A named product only matters for compounds and others; urea is urea.
        let name = productName.trimmingCharacters(in: .whitespaces)
        saved.productName = product.plannedFertilizer == nil ? name : ""
        saved.kilograms = kilograms
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }
}
