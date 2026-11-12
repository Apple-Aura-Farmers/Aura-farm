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
    /// The one sheet slot this screen has for its forms. It carries what to show rather than
    /// a flag, because a sheet reads a flag before the value beside it has arrived.
    @State private var formSheet: FormSheet?
    /// Whether the outline editor is pushed, for marking a plot before picking its farm.
    @State private var markingPlot = false
    /// Set to open a farm's page.
    @State private var openedFarmID: UUID?
    /// Something to do as soon as the list sheet has finished closing.
    @State private var pending: Pending?
    @State private var listDetent = FieldHelperHomeView.collapsed

    /// What the form sheet is showing.
    private enum FormSheet: Identifiable {
        /// Naming a farm that has no land marked yet.
        case addFarm
        /// Land marked on the map, waiting to be filed against a farm.
        case filePlot(Plot)

        var id: String {
            switch self {
            case .addFarm: "add"
            case .filePlot(let plot): plot.id.uuidString
            }
        }
    }

    private enum Pending {
        case add
        case markPlot
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
            .sheet(item: $formSheet, onDismiss: { showFarmList = true }) { sheet in
                switch sheet {
                case .addFarm:
                    FarmFormView()
                case .filePlot(let plot):
                    PlotFarmPickerSheet(plot: plot)
                }
            }
            .navigationDestination(item: $openedFarmID) { id in
                FarmDetailView(farmID: id)
            }
            .navigationDestination(isPresented: $markingPlot) {
                LandOutlineEditorView(corners: [], neighbours: store.farms.neighbours()) { corners in
                    // Set before the editor pops, so reappearing here leaves the list sheet
                    // closed and shows the picker instead.
                    formSheet = .filePlot(Plot(corners: corners))
                }
            }
        }
    }

    // MARK: Screens

    private var mapScreen: some View {
        FarmsOverviewMap(farms: store.farms) { farm in
            request(.open(farm.id))
        }
        // A new map when farms are added, deleted or reshaped, so it refits to them.
        .id(store.farms.flatMap(\.allCorners))
        .ignoresSafeArea()
        // Runs on first showing, whenever a pushed page is popped back, and again whenever the
        // map is rebuilt for a change to the farms. Only the first two should raise the sheet:
        // editing a plot changes the farms while the farm's page is still open, and the sheet
        // must not slide up over it.
        .onAppear {
            if openedFarmID == nil && !markingPlot && formSheet == nil { showFarmList = true }
        }
        .sheet(isPresented: $showFarmList, onDismiss: runPending) {
            FarmListSheet(
                farms: sortedFarms,
                onOpen: { request(.open($0.id)) },
                onAdd: { request(.add) },
                onMarkPlot: { request(.markPlot) }
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
            VStack(spacing: 12) {
                Button("Add a farm") { formSheet = .addFarm }
                    .buttonStyle(.borderedProminent)
                Button("Mark a plot on the map") { markingPlot = true }
            }
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
        case .add: formSheet = .addFarm
        case .markPlot: markingPlot = true
        case .open(let id): openedFarmID = id
        }
    }

    private var sortedFarms: [Farm] {
        store.farms.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

extension View {
    /// Liquid Glass circle where the system has it (iOS 26), frosted material before that.
    @ViewBuilder
    fileprivate func glassCircle() -> some View {
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
                        name: "Subak Jatiluwih",
                        farmerName: "Pak Wayan",
                        plots: [
                            Plot(corners: [
                                GeoPoint(latitude: -8.4095, longitude: 115.1889),
                                GeoPoint(latitude: -8.4095, longitude: 115.1900),
                                GeoPoint(latitude: -8.4105, longitude: 115.1900),
                                GeoPoint(latitude: -8.4105, longitude: 115.1889),
                            ])
                        ])
                ]))
}
