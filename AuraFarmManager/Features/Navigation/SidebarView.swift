import SwiftData
import SwiftUI

/// The inbox, every soil test, and the farms with their fields.
struct SidebarView: View {
    @Binding var selection: SidebarItem?

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Farm.name) private var farms: [Farm]
    @Query private var soilTests: [SoilTest]

    @State private var isAddingFarm = false
    @State private var farmToDelete: Farm?

    var body: some View {
        List(selection: $selection) {
            Section("Soil Tests") {
                Label("Inbox", systemImage: "tray")
                    .badge(inboxCount)
                    .tag(SidebarItem.inbox)
                Label("All Tests", systemImage: "testtube.2")
                    .tag(SidebarItem.allTests)
            }
            Section("Farms") {
                ForEach(farms) { farm in
                    Label(farm.name, systemImage: "leaf")
                        .tag(SidebarItem.farm(farm))
                        .contextMenu {
                            Button("Delete Farm…", role: .destructive) {
                                farmToDelete = farm
                            }
                        }
                    ForEach(farm.sortedFields) { field in
                        Label(field.name, systemImage: "square.grid.2x2")
                            .padding(.leading, 16)
                            .tag(SidebarItem.field(field))
                    }
                }
            }
        }
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .toolbar {
            ToolbarItem {
                Button {
                    isAddingFarm = true
                } label: {
                    Label("New Farm", systemImage: "plus")
                }
                .help("Add a farm")
            }
        }
        .sheet(isPresented: $isAddingFarm) {
            FarmEditorView(farm: nil) { farm in
                selection = .farm(farm)
            }
        }
        .confirmationDialog(
            "Delete \(farmToDelete?.name ?? "this farm")?",
            isPresented: isConfirmingDelete,
            presenting: farmToDelete
        ) { farm in
            Button("Delete Farm", role: .destructive) {
                delete(farm)
            }
        } message: { _ in
            Text("Its fields are deleted too. Soil tests filed under them go back to the inbox.")
        }
    }

    /// Tests waiting to be filed under a field.
    private var inboxCount: Int {
        soilTests.filter { $0.field == nil }.count
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { farmToDelete != nil },
            set: { isShowing in
                if !isShowing { farmToDelete = nil }
            }
        )
    }

    private func delete(_ farm: Farm) {
        switch selection {
        case .farm(let selected) where selected == farm:
            selection = .inbox
        case .field(let field) where field.farm == farm:
            selection = .inbox
        default:
            break
        }
        modelContext.delete(farm)
        try? modelContext.save()
    }
}
