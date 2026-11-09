import SwiftData
import SwiftUI

/// Adds a farm, or edits one.
struct FarmEditorView: View {
    /// nil to add a new farm.
    let farm: Farm?
    /// Called with the farm once it is saved.
    var onSave: (Farm) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var ownerName = ""
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                LabeledTextField(label: "Farm", text: $name, prompt: "For example, Pak Wayan's farm")
                LabeledTextField(label: "Farmer", text: $ownerName, prompt: "Optional")
                LabeledTextField(label: "Village", text: $location, prompt: "Village or district")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
            .formStyle(.grouped)
            .navigationTitle(farm == nil ? "New Farm" : "Edit Farm")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(farm == nil ? "Add Farm" : "Save") {
                        save()
                    }
                    .disabled(trimmed(name).isEmpty)
                }
            }
        }
        .onAppear(perform: load)
    }

    private func load() {
        guard let farm else { return }
        name = farm.name
        ownerName = farm.ownerName
        location = farm.location
        notes = farm.notes
    }

    private func save() {
        let saved: Farm
        if let farm {
            saved = farm
        } else {
            saved = Farm(name: trimmed(name))
            modelContext.insert(saved)
        }
        saved.name = trimmed(name)
        saved.ownerName = trimmed(ownerName)
        saved.location = trimmed(location)
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        onSave(saved)
        dismiss()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespaces)
    }
}
