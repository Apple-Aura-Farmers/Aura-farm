import SwiftData
import SwiftUI

/// A farm: who farms it, its fields and where they are, how their soil life has moved, and every
/// soil test filed under them.
struct FarmDetailView: View {
    @Bindable var farm: Farm

    @Environment(\.modelContext) private var modelContext
    @Environment(\.canEditRecords) private var canEdit
    @State private var isEditingFarm = false
    @State private var isAddingField = false
    @State private var fieldToEdit: Field?
    @State private var fieldToDelete: Field?

    var body: some View {
        List {
            if !subtitle.isEmpty || !farm.notes.isEmpty {
                Section {
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .foregroundStyle(.secondary)
                    }
                    if !farm.notes.isEmpty {
                        Text(farm.notes)
                    }
                }
            }

            Section {
                if farm.fields.isEmpty {
                    Text(
                        canEdit
                            ? "No fields yet. Add the farm's fields, then file soil tests under them."
                            : "No fields yet."
                    )
                    .foregroundStyle(.secondary)
                }
                ForEach(farm.sortedFields) { field in
                    NavigationLink(value: field) {
                        FieldRow(field: field)
                    }
                    .swipeActions {
                        if canEdit {
                            Button("Delete", role: .destructive) {
                                fieldToDelete = field
                            }
                            Button("Edit") {
                                fieldToEdit = field
                            }
                        }
                    }
                }
                if canEdit {
                    Button {
                        isAddingField = true
                    } label: {
                        Label("Add Field", systemImage: "plus")
                    }
                }
            } header: {
                Text("Fields")
            }

            Section("Map") {
                FarmMapView(fields: farm.sortedFields)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }

            Section {
                FieldTrendChart(fields: farm.sortedFields)
            }

            Section("Soil Tests") {
                if farm.soilTests.isEmpty {
                    Text("No soil tests filed under this farm's fields yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(farm.soilTests) { test in
                    NavigationLink(value: test) {
                        SoilTestRow(test: test)
                    }
                }
            }
        }
        .navigationTitle(farm.name)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") {
                        isEditingFarm = true
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingFarm) {
            FarmEditorView(farm: farm)
        }
        .sheet(isPresented: $isAddingField) {
            FieldEditorView(farm: farm, field: nil)
        }
        .sheet(item: $fieldToEdit) { field in
            FieldEditorView(farm: farm, field: field)
        }
        .confirmationDialog(
            "Delete \(fieldToDelete?.name ?? "this field")?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: fieldToDelete
        ) { field in
            Button("Delete Field", role: .destructive) {
                modelContext.delete(field)
                try? modelContext.save()
            }
        } message: { field in
            Text(deleteMessage(for: field))
        }
    }

    /// "Farmer · Village", leaving out whichever is empty.
    private var subtitle: String {
        [farm.ownerName, farm.location]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .joined(separator: " · ")
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { fieldToDelete != nil },
            set: { isShowing in
                if !isShowing { fieldToDelete = nil }
            }
        )
    }

    private func deleteMessage(for field: Field) -> String {
        var message = "Its soil tests go back to the inbox."
        if !field.nutrientTests.isEmpty || !field.seasons.isEmpty {
            message += " Its NPK results and seasons are deleted."
        }
        return message
    }
}
