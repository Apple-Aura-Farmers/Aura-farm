import SwiftUI

/// Every farmer the helper looks after, one row each, with the way through to their land and
/// its test results.
///
/// The same list serves the Results tab and the search tab beside it. Only the search tab
/// carries a field to type into; Results is the whole list, in order. This screen has the
/// navigation bar the map has not, so switching role lives here rather than over the land.
struct FarmersListView: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: (() -> Void)?
    /// Set on the search tab, which is the only copy with a field to type into.
    var isSearch = false

    @Environment(FarmStore.self) private var store

    @State private var query = ""
    /// The farm waiting on a yes to being deleted.
    @State private var farmToDelete: Farm?

    var body: some View {
        NavigationStack {
            searchableList
                .auraBackground()
                .navigationTitle(isSearch ? "" : "Farmers")
                // The search tab hides the navigation bar while the field is in use, so its title
                // is drawn in the content instead.
                .safeAreaInset(edge: .top, spacing: 0) {
                    if isSearch {
                        Text("Farmers")
                            .font(.largeTitle.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .navigationBarTitleDisplayMode(isSearch ? .inline : .automatic)
                .navigationDestination(for: Farm.ID.self) { id in
                    FarmDetailView(farmID: id)
                }
                .toolbar {
                    if let onSwitchRole {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Switch role", systemImage: "arrow.left.arrow.right") {
                                onSwitchRole()
                            }
                        }
                    }
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
            Group {
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
            .listRowBackground(RoundedRectangle(cornerRadius: 16).fill(Color.auraRow))
            .listRowSeparator(.hidden)
        }
        .listRowSpacing(12)
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

    /// Sorted by the farmer, because that is what the row is read by. Nothing typed, or no
    /// field to type into, is the whole list.
    private var shown: [Farm] {
        store.farms
            .matching(isSearch ? query : "")
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
    FarmersListView(onSwitchRole: {})
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
