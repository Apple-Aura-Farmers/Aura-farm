//
//  FieldHelperHomeView.swift
//  AuraFarm
//
//  Created by William Silvano Angga on 09/11/26.
//

import SwiftUI

/// The Field Helper's home: the farms they look after, and a way to add one.
struct FieldHelperHomeView: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @Environment(FarmStore.self) private var store
    @State private var showAddFarm = false
    /// The farm waiting on a yes to being deleted.
    @State private var farmToDelete: Farm?
    /// Set when a farm is tapped on the map, which opens its page.
    @State private var openedFarmID: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if store.farms.isEmpty {
                    emptyState
                } else {
                    farmList
                }
            }
            .safeAreaInset(edge: .top) {
                if let problem = store.problem {
                    Text(problem)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.bar)
                }
            }
            .navigationTitle("My farms")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onSwitchRole) {
                        Label("Switch role", systemImage: "arrow.left.arrow.right")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddFarm = true
                    } label: {
                        Label("Add a farm", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddFarm) {
                FarmFormView()
            }
            .navigationDestination(item: $openedFarmID) { id in
                FarmDetailView(farmID: id)
            }
            .confirmationDialog(
                "Delete this farm?",
                isPresented: Binding(
                    get: { farmToDelete != nil },
                    set: { if !$0 { farmToDelete = nil } }),
                presenting: farmToDelete
            ) { farm in
                Button("Delete \(farm.farmerName)'s farm", role: .destructive) {
                    store.delete(farm)
                }
            } message: { _ in
                Text("The farm and its outline will be removed from this phone.")
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No farms yet", systemImage: "leaf")
        } description: {
            Text("Add the farms you look after to see their land and soil details here.")
        } actions: {
            Button("Add a farm") { showAddFarm = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var farmList: some View {
        VStack(spacing: 0) {
            FarmsOverviewMap(farms: store.farms) { farm in
                openedFarmID = farm.id
            }
            // A new map when farms are added, deleted or reshaped, so it refits to them.
            .id(store.farms.flatMap(\.corners))
            .frame(height: 280)

            List {
                ForEach(sortedFarms) { farm in
                    NavigationLink {
                        FarmDetailView(farmID: farm.id)
                    } label: {
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
        }
    }

    private var sortedFarms: [Farm] {
        store.farms.sorted {
            $0.farmerName.localizedStandardCompare($1.farmerName) == .orderedAscending
        }
    }

    private func row(for farm: Farm) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(farm.farmerName).font(.headline)
            if let area = farm.areaSquareMetres {
                Text(LandGeometry.areaDescription(squareMetres: area))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    FieldHelperHomeView(onSwitchRole: {})
        .environment(FarmStore(fileURL: nil))
}
