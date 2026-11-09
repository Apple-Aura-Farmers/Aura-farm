import AuraFarmKit
import SwiftData
import SwiftUI

/// One field: what to do about it, where it is, its NPK results, what the microscope counted, and
/// every soil test filed under it.
struct FieldDetailView: View {
    @Bindable var field: Field
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext
    @State private var isAddingNutrientTest = false
    @State private var nutrientTestToEdit: NutrientTest?
    @State private var nutrientTestToDelete: NutrientTest?
    @State private var isEditingField = false
    @State private var isDrawingBoundary = false

    var body: some View {
        VSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    advice
                    FieldMapPreview(field: field) {
                        isDrawingBoundary = true
                    }
                    nutrientList
                    NutrientTrendChart(tests: field.nutrientTests)
                    SeasonsSection(field: field, doses: FieldAdvice.advice(for: field)?.doses ?? [])
                    latestCounts
                    FieldTrendChart(fields: [field], emptyMessage: Self.countTrendEmptyMessage)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 280, idealHeight: 480)

            SoilTestTable(tests: field.sortedSoilTests, selection: $selection)
                .frame(minHeight: 140)
        }
        .navigationTitle(field.name)
        .navigationSubtitle(field.farm?.name ?? "")
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingNutrientTest = true
                } label: {
                    Label("Add NPK Results", systemImage: "plus")
                }
                .help("Add N, P and K results from a soil test kit or lab")
            }
            ToolbarItem {
                Button {
                    isEditingField = true
                } label: {
                    Label("Edit Field", systemImage: "pencil")
                }
                .help("Edit the field's name, crop and area")
                .disabled(field.farm == nil)
            }
        }
        .sheet(isPresented: $isAddingNutrientTest) {
            NutrientTestEditorView(field: field, test: nil)
        }
        .sheet(item: $nutrientTestToEdit) { test in
            NutrientTestEditorView(field: field, test: test)
        }
        .sheet(isPresented: $isDrawingBoundary) {
            FieldBoundaryEditorView(field: field)
        }
        .sheet(isPresented: $isEditingField) {
            if let farm = field.farm {
                FieldEditorView(farm: farm, field: field)
            }
        }
        .confirmationDialog(
            "Delete these NPK results?",
            isPresented: isConfirmingDelete,
            presenting: nutrientTestToDelete
        ) { test in
            Button("Delete", role: .destructive) {
                delete(test)
            }
        } message: { test in
            Text(
                "The results from \(test.testedAt.formatted(date: .abbreviated, time: .omitted)) are deleted."
            )
        }
    }

    private static let countTrendEmptyMessage =
        "The trend appears once two or more soil tests are filed under this field."

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(field.name)
                .font(.largeTitle.bold())
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var advice: some View {
        if let advice = FieldAdvice.advice(for: field) {
            SoilAdviceView(advice: advice)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("What to Do")
                    .font(.headline)
                Text(
                    "Add NPK results from a soil test kit or lab, or file a soil test under this field, "
                        + "to see what to do."
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var nutrientList: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("NPK Results")
                    .font(.headline)
                Spacer()
                Button("Add NPK Results…") {
                    isAddingNutrientTest = true
                }
            }
            if field.nutrientTests.isEmpty {
                Text("No NPK results yet. Type them in from the soil test kit or a lab report.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(field.sortedNutrientTests) { test in
                    NutrientTestRow(test: test)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            nutrientTestToEdit = test
                        }
                        .contextMenu {
                            Button("Edit Results…") {
                                nutrientTestToEdit = test
                            }
                            Button("Delete Results…", role: .destructive) {
                                nutrientTestToDelete = test
                            }
                        }
                }
            }
        }
    }

    @ViewBuilder
    private var latestCounts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Microscope Count")
                .font(.headline)
            if let latest = field.latestSoilTest {
                if latest.organismCounts.isEmpty {
                    Text("No organisms were counted on the last slide. Check the preparation and test again.")
                        .foregroundStyle(.secondary)
                } else {
                    OrganismCountChart(counts: latest.sortedCounts)
                    Text(
                        "Raw counts from sample \(latest.sampleID), "
                            + "\(latest.recordedAt.formatted(date: .abbreviated, time: .omitted)). "
                            + "Not a soil health rating."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } else {
                Text("No soil test filed under this field yet. File one from the inbox.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Pak Made's farm · Rice · 0.5 ha"
    private var subtitle: String {
        var parts: [String] = []
        if let farm = field.farm {
            parts.append(farm.name)
        }
        parts.append(field.crop)
        if let area = field.areaHectares {
            parts.append("\(area.formatted(.number)) ha")
        } else {
            parts.append("Area not entered")
        }
        return parts.joined(separator: " · ")
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { nutrientTestToDelete != nil },
            set: { isShowing in
                if !isShowing { nutrientTestToDelete = nil }
            }
        )
    }

    private func delete(_ test: NutrientTest) {
        modelContext.delete(test)
        try? modelContext.save()
    }
}
