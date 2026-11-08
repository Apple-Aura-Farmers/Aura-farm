import SwiftData
import SwiftUI

/// Soil tests as a table: when, which sample, where it is filed, and what was counted.
struct SoilTestTable: View {
    let tests: [SoilTest]
    @Binding var selection: PersistentIdentifier?

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Table(tests, selection: $selection) {
            TableColumn("Recorded") { test in
                Text(test.recordedAt, format: .dateTime.day().month().year().hour().minute())
            }
            .width(min: 130, ideal: 150)
            TableColumn("Sample") { test in
                Text(test.sampleID)
            }
            .width(min: 70, ideal: 90)
            TableColumn("Farm and Field") { test in
                Text(test.placeLabel)
                    .foregroundStyle(test.field == nil ? Color.secondary : Color.primary)
            }
            TableColumn("Organisms") { test in
                Text(test.totalCount, format: .number)
                    .monospacedDigit()
            }
            .width(min: 70, ideal: 80)
            TableColumn("Frames") { test in
                Text(test.frameCount, format: .number)
                    .monospacedDigit()
            }
            .width(min: 50, ideal: 60)
        }
        .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
            Button("Delete", role: .destructive) {
                delete(ids)
            }
            .disabled(ids.isEmpty)
        }
    }

    private func delete(_ ids: Set<PersistentIdentifier>) {
        if let selection, ids.contains(selection) {
            self.selection = nil
        }
        for test in tests where ids.contains(test.persistentModelID) {
            modelContext.delete(test)
        }
        try? modelContext.save()
    }
}
