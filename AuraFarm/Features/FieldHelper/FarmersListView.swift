import SwiftUI

/// Every farmer the helper looks after, one row each, with the way through to their land and
/// its test results.
///
/// The same list serves the Results tab and the search tab beside it. On the search tab it
/// carries the search field, so what is typed into the tab bar filters these rows; everywhere
/// else it is the plain list.
struct FarmersListView: View {
    /// Set on the search tab, which is the only copy that shows a search field.
    var isSearch = false

    @Environment(FarmStore.self) private var store

    @State private var query = ""
    /// The farm waiting on a yes to being deleted.
    @State private var farmToDelete: Farm?

    var body: some View {
        NavigationStack {
            searchableList
                .navigationTitle("Farmers")
                .navigationDestination(for: Farm.ID.self) { id in
                    FarmDetailView(farmID: id)
                }
        }
    }

    @ViewBuilder
    private var searchableList: some View {
        if isSearch {
            list.searchable(text: $query, prompt: "Farmers or Locations")
        } else {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(shown) { farm in
                NavigationLink(value: farm.id) {
                    row(for: farm)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        farmToDelete = farm
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .animation(.snappy, value: shown.map(\.id))
        .refreshable { await store.pull() }
        .overlay { emptyState }
        .confirmationDialog(
            "Delete this farm?",
            isPresented: Binding(
                get: { farmToDelete != nil },
                set: { if !$0 { farmToDelete = nil } }),
            presenting: farmToDelete
        ) { farm in
            Button("Delete \(farm.name)", role: .destructive) {
                Task { await store.remove(farm) }
            }
        } message: { _ in
            Text("The farm and its plots will be removed from this phone and the records.")
        }
    }

    /// Sorted by the farmer, because that is what the row is read by.
    private var shown: [Farm] {
        store.farms
            .matching(query)
            .sorted { $0.farmerName.localizedStandardCompare($1.farmerName) == .orderedAscending }
    }

    private func row(for farm: Farm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(farm.farmerName)
                .font(.headline)
            Text(farm.locationLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        if shown.isEmpty {
            if store.farms.isEmpty {
                ContentUnavailableView {
                    Label("No farmers yet", systemImage: "person.2")
                } description: {
                    Text("Mark a farmer's land on the Plots tab to see them here.")
                }
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

#Preview {
    FarmersListView(isSearch: true)
        .environment(
            FarmStore(
                fileURL: nil,
                farms: [
                    Farm(
                        name: "Pak Wayan", farmerName: "Pak Wayan",
                        plots: [Plot(name: "Tabanan", corners: [])]),
                    Farm(name: "Tanuh Sutera", farmerName: "Pak Agung"),
                ]))
}
