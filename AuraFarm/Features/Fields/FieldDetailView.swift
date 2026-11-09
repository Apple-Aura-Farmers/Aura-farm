import AuraFarmKit
import SwiftData
import SwiftUI

/// One field: what to do about it, where it is, its NPK results, its seasons, what the
/// microscope counted, and every soil test filed under it.
///
/// Field helpers see all of it, so they can explain the plan to the farmer; only the program
/// manager changes it.
struct FieldDetailView: View {
    @Bindable var field: Field

    @Environment(\.modelContext) private var modelContext
    @Environment(\.canEditRecords) private var canEdit
    @State private var isAddingNutrientTest = false
    @State private var nutrientTestToEdit: NutrientTest?
    @State private var nutrientTestToDelete: NutrientTest?
    @State private var isEditingField = false
    @State private var isDrawingBoundary = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                advice
                FieldMapPreview(field: field, onEdit: canEdit ? { isDrawingBoundary = true } : nil)
                nutrientList
                NutrientTrendChart(tests: field.nutrientTests)
                SeasonsSection(field: field, doses: FieldAdvice.advice(for: field)?.doses ?? [])
                latestCounts
                FieldTrendChart(fields: [field], emptyMessage: Self.countTrendEmptyMessage)
                soilTests
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(field.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if canEdit {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            isAddingNutrientTest = true
                        } label: {
                            Label("Add NPK Results", systemImage: "plus")
                        }
                        Button {
                            isDrawingBoundary = true
                        } label: {
                            Label(boundaryActionTitle, systemImage: "map")
                        }
                        if field.farm != nil {
                            Button {
                                isEditingField = true
                            } label: {
                                Label("Edit Field", systemImage: "pencil")
                            }
                        }
                    } label: {
                        Label("Change", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $isAddingNutrientTest) {
            NutrientTestEditorView(field: field, test: nil)
        }
        .sheet(isPresented: isEditingNutrientTest) {
            if let test = nutrientTestToEdit {
                NutrientTestEditorView(field: field, test: test)
            }
        }
        .fullScreenCover(isPresented: $isDrawingBoundary) {
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
            titleVisibility: .visible,
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

    private var boundaryActionTitle: String {
        field.boundary == nil ? "Draw Boundary" : "Edit Boundary"
    }

    private static let countTrendEmptyMessage =
        "The trend appears once two or more soil tests are filed under this field."

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    canEdit
                        ? "Add NPK results from a soil test kit or lab, or file a soil test under this "
                            + "field, to see what to do."
                        : "No plan yet. It appears once the program manager adds NPK results, or a soil "
                            + "test is filed under this field."
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
                if canEdit {
                    Button("Add") {
                        isAddingNutrientTest = true
                    }
                }
            }
            if field.nutrientTests.isEmpty {
                Text(
                    canEdit
                        ? "No NPK results yet. Type them in from the soil test kit or a lab report."
                        : "No NPK results yet."
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(field.sortedNutrientTests) { test in
                    NutrientTestRow(test: test)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if canEdit { nutrientTestToEdit = test }
                        }
                        .contextMenu {
                            if canEdit {
                                Button("Edit Results") {
                                    nutrientTestToEdit = test
                                }
                                Button("Delete Results", role: .destructive) {
                                    nutrientTestToDelete = test
                                }
                            }
                        }
                }
                if canEdit {
                    Text("Tap a result to change it; touch and hold to delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

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
                Text("No soil test filed under this field yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var soilTests: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Soil Tests")
                .font(.headline)
            if field.soilTests.isEmpty {
                Text("None yet. Save a test from its result screen and pick this field.")
                    .foregroundStyle(.secondary)
            }
            ForEach(field.sortedSoilTests) { test in
                NavigationLink(value: test) {
                    HStack {
                        SoilTestRow(test: test, showsPlace: false)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "Pak Wayan's farm · Rice · 0.6 ha"
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

    private var isEditingNutrientTest: Binding<Bool> {
        Binding(
            get: { nutrientTestToEdit != nil },
            set: { isShowing in
                if !isShowing { nutrientTestToEdit = nil }
            }
        )
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
