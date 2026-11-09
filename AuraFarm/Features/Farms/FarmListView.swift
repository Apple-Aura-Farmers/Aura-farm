import SwiftData
import SwiftUI

/// Every farm, with its fields and when it was last tested. The program manager adds and
/// deletes farms here; field helpers only look.
struct FarmListView: View {
    @Query(sort: \Farm.name) private var farms: [Farm]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.canEditRecords) private var canEdit
    @State private var isAddingFarm = false
    @State private var farmToDelete: Farm?

    var body: some View {
        Group {
            if farms.isEmpty {
                ContentUnavailableView {
                    Label("No Farms Yet", systemImage: "leaf")
                } description: {
                    Text(
                        canEdit
                            ? "Add the farms the helpers visit, then their fields."
                            : "The program manager adds the farms. Switch role at the top to add one."
                    )
                } actions: {
                    if canEdit {
                        Button("Add Farm") { isAddingFarm = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                List {
                    ForEach(farms) { farm in
                        NavigationLink(value: farm) {
                            row(for: farm)
                        }
                        .swipeActions {
                            if canEdit {
                                Button("Delete", role: .destructive) {
                                    farmToDelete = farm
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Farms")
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingFarm = true
                    } label: {
                        Label("Add Farm", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingFarm) {
            FarmEditorView(farm: nil)
        }
        .confirmationDialog(
            "Delete \(farmToDelete?.name ?? "this farm")?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: farmToDelete
        ) { farm in
            Button("Delete Farm", role: .destructive) {
                modelContext.delete(farm)
                try? modelContext.save()
            }
        } message: { _ in
            Text("Its fields, NPK results and seasons are deleted too. Its soil tests go back to the inbox.")
        }
    }

    private func row(for farm: Farm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(farm.name)
                .font(.headline)
            Text(summary(of: farm))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Wayan Sudarma · Jatiluwih · 2 fields"
    private func summary(of farm: Farm) -> String {
        var parts = [farm.ownerName, farm.location]
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        parts.append(farm.fields.count == 1 ? "1 field" : "\(farm.fields.count) fields")
        return parts.joined(separator: " · ")
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { farmToDelete != nil },
            set: { isShowing in
                if !isShowing { farmToDelete = nil }
            }
        )
    }
}
