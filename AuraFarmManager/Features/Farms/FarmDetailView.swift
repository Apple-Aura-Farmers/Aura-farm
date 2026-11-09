import SwiftData
import SwiftUI

/// A farm: who farms it, its fields and where they are, how their soil life has moved, and every
/// soil test filed under them.
struct FarmDetailView: View {
    @Bindable var farm: Farm
    @Binding var selection: PersistentIdentifier?
    /// Opens a field's own page, with its NPK results and what to do about it.
    var onOpenField: (Field) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @State private var isEditingFarm = false
    @State private var isAddingField = false
    @State private var fieldToEdit: Field?
    @State private var fieldToDelete: Field?

    var body: some View {
        VSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    fieldList
                    FarmMapView(fields: farm.sortedFields, onOpenField: onOpenField)
                    FieldTrendChart(fields: farm.sortedFields)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 240, idealHeight: 360)

            SoilTestTable(tests: farm.soilTests, selection: $selection)
                .frame(minHeight: 160)
        }
        .navigationTitle(farm.name)
        .toolbar {
            ToolbarItem {
                Button {
                    isEditingFarm = true
                } label: {
                    Label("Edit Farm", systemImage: "pencil")
                }
                .help("Edit the farm's details")
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
            presenting: fieldToDelete
        ) { field in
            Button("Delete Field", role: .destructive) {
                delete(field)
            }
        } message: { field in
            Text(deleteMessage(for: field))
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(farm.name)
                .font(.largeTitle.bold())
            if !subtitle.isEmpty {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            }
            if !farm.notes.isEmpty {
                Text(farm.notes)
                    .padding(.top, 4)
            }
        }
    }

    private var fieldList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fields")
                    .font(.headline)
                Spacer()
                Button("Add Field…") {
                    isAddingField = true
                }
            }
            if farm.fields.isEmpty {
                Text("No fields yet. Add the farm's fields, then file soil tests under them.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(farm.sortedFields) { field in
                    Button {
                        onOpenField(field)
                    } label: {
                        FieldRow(field: field)
                    }
                    .buttonStyle(.plain)
                    .help("Open the field's NPK results and what to do")
                    .contextMenu {
                        Button("Open Field") {
                            onOpenField(field)
                        }
                        Button("Edit Field…") {
                            fieldToEdit = field
                        }
                        Button("Delete Field…", role: .destructive) {
                            fieldToDelete = field
                        }
                    }
                }
            }
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
        if !field.nutrientTests.isEmpty {
            message += " Its NPK results are deleted."
        }
        return message
    }

    /// The field's soil tests are kept and go back to the inbox. Its NPK results are deleted.
    private func delete(_ field: Field) {
        modelContext.delete(field)
        try? modelContext.save()
    }
}
