import SwiftUI

/// The Plots tab: a full-screen map of every plot the helper looks after.
///
/// The map runs edge to edge with no navigation bar over it. The two controls that would sit
/// in that bar — switching role, and adding land — float on the map instead, clear of the tab
/// bar along the bottom.
///
/// SwiftUI can only show one sheet at a time from a screen, and a sheet would sit on top of
/// any page pushed from here, so the one sheet slot carries whichever form is wanted and the
/// card for a tapped plot closes itself before opening that plot's farm.
struct FieldHelperHomeView: View {
    /// Sends the person back to the role picker.
    var onSwitchRole: () -> Void

    @Environment(FarmStore.self) private var store

    /// The one sheet slot this screen has for its forms. It carries what to show rather than
    /// a flag, because a sheet reads a flag before the value beside it has arrived.
    @State private var formSheet: FormSheet?
    /// Whether the outline editor is pushed, for marking a plot before picking its farm.
    @State private var markingPlot = false
    /// Set to open a farm's page.
    @State private var openedFarmID: UUID?
    /// The plot whose card is showing over the map, if any.
    @State private var selection: Selection?

    /// A plot the helper tapped, kept with its farm so the card can name the farmer.
    private struct Selection: Equatable {
        var farm: Farm
        var plot: Plot
    }

    /// What the form sheet is showing.
    private enum FormSheet: Identifiable {
        /// Naming a farm that has no land marked yet.
        case addFarm
        /// Land marked on the map, waiting to be filed against a farm.
        case filePlot(Plot)
        /// A plot the helper tapped on the map.
        case plot(Selection)

        var id: String {
            switch self {
            case .addFarm: "add"
            case .filePlot(let plot): plot.id.uuidString
            case .plot(let selection): selection.plot.id.uuidString
            }
        }
    }

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
            .overlay(alignment: .bottomTrailing) { addButton }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $formSheet) { sheet in
                switch sheet {
                case .addFarm:
                    FarmFormView()
                case .filePlot(let plot):
                    NewPlotFormView(corners: plot.corners) {
                        // Back to the map with these corners, rather than starting again.
                        formSheet = nil
                        markingPlot = true
                    }
                case .plot(let selection):
                    plotCard(selection)
                        // Only as tall as it needs to be, so the land stays in view behind it.
                        .presentationDetents([.height(240)])
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled)
                }
            }
            .navigationDestination(item: $openedFarmID) { id in
                FarmDetailView(farmID: id)
            }
            .navigationDestination(isPresented: $markingPlot) {
                LandOutlineEditorView(corners: [], neighbours: store.farms.neighbours()) { corners in
                    formSheet = .filePlot(Plot(corners: corners))
                }
            }
        }
    }

    // MARK: Screens

    private var mapScreen: some View {
        FarmsOverviewMap(farms: store.farms, onOpen: show, onDeselect: deselect, selected: selection?.plot.id)
            // A new map when farms are added, deleted or reshaped, so it refits to them.
            .id(store.farms.flatMap(\.allCorners))
            .ignoresSafeArea()
            // Reads the records once when the map appears; after that it is the pull on the
            // farmers list.
            .task { await store.pull() }
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

    // MARK: The plot the helper tapped

    /// Opens the card for a plot.
    private func show(_ farm: Farm, _ plot: Plot) {
        let selection = Selection(farm: farm, plot: plot)
        self.selection = selection
        formSheet = .plot(selection)
    }

    /// Tapping empty map puts the card away.
    private func deselect() {
        guard selection != nil else { return }
        selection = nil
        if case .plot = formSheet { formSheet = nil }
    }

    /// What a tapped plot says for itself: whose it is, which of theirs, how big, and the way
    /// through to its tests. The sheet it sits in gives it the drag and the dismiss, so there
    /// is no card chrome of its own here.
    private func plotCard(_ selection: Selection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(selection.farm.farmerName) · \(selection.farm.title(of: selection.plot))")
                .font(.title2.bold())
            if !selection.plot.name.isEmpty {
                Text(selection.plot.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let area = selection.plot.areaSquareMetres {
                Text(LandGeometry.areaDescription(squareMetres: area))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                // The sheet goes first: pushing out from under a sheet leaves it hanging over
                // the page that was pushed.
                formSheet = nil
                openedFarmID = selection.farm.id
            } label: {
                Text("View Test Results")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(
                FarmerColour.colour(
                    for: selection.farm.farmerName, among: store.farms.map(\.farmerName)))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: Floating controls

    /// Land is added the way the map does it: walk the edge first, name it afterwards. A farm
    /// with no land yet can be started here too.
    private var addButton: some View {
        Menu {
            Button {
                selection = nil
                markingPlot = true
            } label: {
                Label("Mark a plot on the map", systemImage: "mappin.and.ellipse")
            }
            Button {
                formSheet = .addFarm
            } label: {
                Label("New farm", systemImage: "leaf")
            }
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
                .glassCircle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add")
        .padding(.trailing, 16)
        // Clear of the floating tab bar along the bottom.
        .padding(.bottom, 80)
    }

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
