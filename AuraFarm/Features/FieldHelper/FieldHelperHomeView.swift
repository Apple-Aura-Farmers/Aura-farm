import SwiftUI

/// The Field Helper's home: a full-screen map of every farm they look after, with the list of
/// farms in a sheet that pulls up from the bottom.
///
/// The map runs edge to edge with no navigation bar over it; the one control that bar held,
/// switching role, floats on the map instead.
///
/// The sheet is always up while this screen is showing. SwiftUI can only show one sheet at a
/// time from a screen, and a sheet would sit on top of any page pushed from here, so anything
/// that opens something else (a farm's page, the add form) asks the sheet to close first and
/// does its work once it has gone. The sheet comes back when this screen reappears.
struct FieldHelperHomeView: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @Environment(FarmStore.self) private var store

    @State private var showFarmList = false
    @State private var showAddFarm = false
    /// Set to open a farm's page.
    @State private var openedFarmID: UUID?
    /// Something to do as soon as the list sheet has finished closing.
    @State private var pending: Pending?
    @State private var listDetent = FieldHelperHomeView.collapsed

    private enum Pending {
        case add
        case open(UUID)
    }

    /// Just the title row showing, so the map has the room.
    private static let collapsed = PresentationDetent.height(88)

    var body: some View {
        NavigationStack {
            Group {
                if store.farms.isEmpty {
                    emptyState
                } else {
                    mapScreen
                }
            }
            .overlay(alignment: .topLeading) { switchRoleButton }
            .overlay(alignment: .top) { problemBanner }
            .toolbar(.hidden, for: .navigationBar)
            .onChange(of: store.farms.isEmpty) { _, isEmpty in
                // Deleting the last farm removes the map this sheet hangs from.
                if isEmpty { showFarmList = false }
            }
            .sheet(isPresented: $showAddFarm, onDismiss: { showFarmList = true }) {
                FarmFormView()
            }
            .navigationDestination(item: $openedFarmID) { id in
                FarmDetailView(farmID: id)
            }
        }
    }

    // MARK: Screens

    private var mapScreen: some View {
        FarmsOverviewMap(farms: store.farms) { farm in
            request(.open(farm.id))
        }
        // A new map when farms are added, deleted or reshaped, so it refits to them.
        .id(store.farms.flatMap(\.corners))
        .ignoresSafeArea()
        // Runs on first showing and whenever a pushed page is popped back.
        .onAppear { showFarmList = true }
        .sheet(isPresented: $showFarmList, onDismiss: runPending) {
            FarmListSheet(
                farms: sortedFarms,
                onOpen: { request(.open($0.id)) },
                onAdd: { request(.add) }
            )
            .presentationDetents([Self.collapsed, .medium, .large], selection: $listDetent)
            // The map stays tappable until the sheet is pulled past half height.
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
            // At half height, dragging the list scrolls it instead of resizing the sheet. The
            // sheet is still resized by dragging its title row or the handle.
            .presentationContentInteraction(.scrolls)
            .interactiveDismissDisabled()
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

    // MARK: Floating controls

    private var switchRoleButton: some View {
        Button(action: onSwitchRole) {
            Image(systemName: "arrow.left.arrow.right")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Switch role")
        .padding(.leading, 16)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var problemBanner: some View {
        if let problem = store.problem {
            Text(problem)
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 72)
                .padding(.top, 8)
        }
    }

    // MARK: Closing the sheet before doing something else

    private func request(_ action: Pending) {
        if showFarmList {
            pending = action
            showFarmList = false
        } else {
            run(action)
        }
    }

    private func runPending() {
        guard let action = pending else { return }
        pending = nil
        run(action)
    }

    private func run(_ action: Pending) {
        switch action {
        case .add: showAddFarm = true
        case .open(let id): openedFarmID = id
        }
    }

    private var sortedFarms: [Farm] {
        store.farms.sorted {
            $0.farmerName.localizedStandardCompare($1.farmerName) == .orderedAscending
        }
    }
}

private extension View {
    /// Liquid Glass circle where the system has it (iOS 26), frosted material before that.
    @ViewBuilder
    func glassCircle() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .circle)
        } else {
            background(.regularMaterial, in: Circle())
        }
    }
}

#Preview {
    FieldHelperHomeView(onSwitchRole: {})
        .environment(
            FarmStore(
                fileURL: nil,
                farms: [
                    Farm(
                        farmerName: "Pak Wayan",
                        corners: [
                            GeoPoint(latitude: -8.4095, longitude: 115.1889),
                            GeoPoint(latitude: -8.4095, longitude: 115.1900),
                            GeoPoint(latitude: -8.4105, longitude: 115.1900),
                            GeoPoint(latitude: -8.4105, longitude: 115.1889),
                        ])
                ]))
}
