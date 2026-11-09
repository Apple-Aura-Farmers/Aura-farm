import SwiftData
import SwiftUI

/// Adds a field to a farm, or edits one.
struct FieldEditorView: View {
    let farm: Farm
    /// nil to add a new field.
    let field: Field?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var crop = "Rice"
    /// Typed as text so an empty box means "not entered" rather than zero.
    @State private var area = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledTextField(label: "Name", text: $name, prompt: "For example, North paddy")
                LabeledTextField(label: "Crop", text: $crop, prompt: "Rice")
                LabeledTextField(label: "Area (ha)", text: $area, prompt: "Optional", keyboard: .decimalPad)
            }
            .formStyle(.grouped)
            .navigationTitle(field == nil ? "New Field on \(farm.name)" : "Edit Field")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(field == nil ? "Add Field" : "Save") {
                        save()
                    }
                    .disabled(trimmed(name).isEmpty || (!trimmed(area).isEmpty && areaHectares == nil))
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Accepts a decimal comma as well as a point.
    private var areaHectares: Double? {
        Double(trimmed(area).replacingOccurrences(of: ",", with: "."))
    }

    private func load() {
        guard let field else { return }
        name = field.name
        crop = field.crop
        area = field.areaHectares.map { $0.formatted(.number) } ?? ""
    }

    private func save() {
        let saved: Field
        if let field {
            saved = field
        } else {
            saved = Field(name: trimmed(name))
            modelContext.insert(saved)
            saved.farm = farm
        }
        saved.name = trimmed(name)
        saved.crop = trimmed(crop).isEmpty ? "Rice" : trimmed(crop)
        saved.areaHectares = areaHectares
        try? modelContext.save()
        dismiss()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
