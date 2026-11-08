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
        VStack(alignment: .leading, spacing: 0) {
            Text(field == nil ? "New Field on \(farm.name)" : "Edit Field")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                TextField("Field name", text: $name, prompt: Text("For example, North paddy"))
                TextField("Crop", text: $crop)
                TextField("Area in hectares", text: $area, prompt: Text("Optional"))
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(field == nil ? "Add Field" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmed(name).isEmpty || (!trimmed(area).isEmpty && areaHectares == nil))
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 420)
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
