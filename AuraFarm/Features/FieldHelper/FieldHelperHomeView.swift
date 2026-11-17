import MapKit
import SwiftUI

/// The Plots tab: a map of every plot the helper looks after, under a bar carrying the one
/// control it needs, which is marking new land.
///
/// SwiftUI can only show one sheet at a time from a screen, and a sheet would sit on top of
/// any page pushed from here, so the one sheet slot carries whichever form is wanted and the
/// card for a tapped plot closes itself before opening that plot's farm.
struct FieldHelperHomeView: View {
    /// Where the map is looking. Owned by the tabs, so the Plots tab and the search tab beside
    /// it show the same land and a search can send both somewhere.
    @Binding var camera: MapCameraPosition
    /// Set on the copy behind the search tab, which is the only one with a field to type into.
    var isSearch = false

    @Environment(FarmStore.self) private var store

    /// What has been typed into the search field, on the copy that has one.
    @State private var query = ""
    /// A plot just filed, waiting for its form to finish closing so its card can open.
    @State private var justFiled: Selection?
    /// Whether the "Plot is Created" note is showing.
    @State private var filedNotice = false
    /// The one sheet slot this screen has for its forms. It carries what to show rather than
    /// a flag, because a sheet reads a flag before the value beside it has arrived.
    @State private var formSheet: FormSheet?
    /// The outline editor, when it is pushed. It carries the land to open on, so Edit from the
    /// New Plot form shows the dots already placed rather than an empty map.
    @State private var outline: Outline?
    /// Set to open a farm's page.
    @State private var openedFarmID: UUID?
    /// The plot whose card is showing over the map, if any.
    @State private var selection: Selection?

    /// Land marked on the map and what has been typed about it so far. It travels between the
    /// form and the outline editor, so a trip to the map and back loses neither.
    private struct Draft: Hashable, Identifiable {
        var id = UUID()
        var corners: [GeoPoint] = []
        var farmer = ""
        var plot = ""
    }

    /// A push of the outline editor: the draft it opens on, and whether the helper came from
    /// the New Plot form, which is where leaving the editor has to put them back.
    private struct Outline: Hashable {
        var draft = Draft()
        var fromForm = false
    }

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
        case filePlot(Draft)
        /// A plot the helper tapped on the map.
        case plot(Selection)

        var id: String {
            switch self {
            case .addFarm: "add"
            case .filePlot(let draft): draft.id.uuidString
            case .plot(let selection): selection.plot.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            withSearch(
                Group {
                    if store.farms.isEmpty {
                        emptyState
                    } else {
                        mapScreen
                    }
                }
            )
            .overlay(alignment: .top) { searchResults }
            .overlay(alignment: .top) { problemBanner }
            .overlay(alignment: .top) { filedBanner }
            // On the screen rather than on the map, because a phone with no farms yet shows no
            // map, and that is exactly the phone with everything to read.
            .task { await store.pull() }
            .navigationBarTitleDisplayMode(.inline)
            // There is nothing scrolling under these bars, only the map, so the system has no
            // edge to fade against and draws a hard band of tinted blur across the land. The
            // bars float over it instead, which is what the design has.
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbarBackgroundVisibility(.hidden, for: .tabBar)
            .toolbar {
                // Not on the search copy, where the bar belongs to the field.
                if !isSearch {
                    ToolbarItem(placement: .topBarTrailing) { addButton }
                }
            }
            .sheet(item: $formSheet, onDismiss: openJustFiled) { sheet in
                switch sheet {
                case .addFarm:
                    FarmFormView()
                case .filePlot(let draft):
                    NewPlotFormView(
                        corners: draft.corners, farmer: draft.farmer, plot: draft.plot,
                        // Filing a plot ends on that plot's card, the same card tapping the
                        // land opens, rather than on a map with nothing picked out on it.
                        onSaved: { farm, plot in justFiled = Selection(farm: farm, plot: plot) }
                    ) { farmer, plot in
                        // Back to the map with these corners, rather than starting again.
                        formSheet = nil
                        outline = Outline(
                            draft: Draft(corners: draft.corners, farmer: farmer, plot: plot),
                            fromForm: true)
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
            .navigationDestination(item: $outline) { outline in
                LandOutlineEditorView(
                    corners: outline.draft.corners, neighbours: store.farms.neighbours()
                ) { corners in
                    var draft = outline.draft
                    draft.corners = corners
                    formSheet = .filePlot(draft)
                } onCancel: {
                    // Editing land that was already marked: leaving goes back to the form it
                    // was being named in, with the outline as it was before Edit.
                    if outline.fromForm { formSheet = .filePlot(outline.draft) }
                }
            }
        }
    }

    // MARK: Screens

    private var mapScreen: some View {
        FarmsOverviewMap(
            farms: store.farms, camera: $camera, onOpen: show, onDeselect: deselect,
            selected: selection?.plot.id
        )
        .ignoresSafeArea()
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
                Button("Mark a plot on the map") { outline = Outline() }
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

    /// Opens the card for the plot that was just filed, once its form has finished closing. A
    /// sheet cannot be swapped for another while it is still on screen, so this waits for the
    /// form's dismissal rather than running at the moment the plot is saved.
    private func openJustFiled() {
        guard let filed = justFiled else { return }
        justFiled = nil
        show(filed.farm, filed.plot)
        withAnimation(.snappy) { filedNotice = true }
    }

    // MARK: Searching

    /// The field, on the copy of this screen behind the search tab. The other copy is the same
    /// map with no field over it, so moving between the two leaves the land where it is.
    @ViewBuilder
    private func withSearch(_ content: some View) -> some View {
        if isSearch {
            content.searchable(text: $query, prompt: "Farmers or Locations")
        } else {
            content
        }
    }

    /// What has been typed matches, over the map rather than on a screen of its own. Nothing
    /// typed shows nothing, so expanding the field leaves the land in view.
    @ViewBuilder
    private var searchResults: some View {
        if isSearch, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let found = store.farms.matching(query)
            ScrollView {
                if found.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .padding(.top, 60)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(found) { farm in
                            Button {
                                focus(on: farm)
                            } label: {
                                resultRow(farm)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
            .background(.regularMaterial)
        }
    }

    private func resultRow(_ farm: Farm) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(farm.farmerName)
                .font(.headline)
            Text(farm.locationLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    /// Sends the map to all of one farmer's land, and puts the results away so it can be seen.
    private func focus(on farm: Farm) {
        query = ""
        selection = nil
        camera = FarmsOverviewMap.fitting([farm])
        // The keyboard would otherwise sit over half the land that was just searched for.
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 20)
    }

    // MARK: Controls

    /// Land is marked the way the map does it: drop the dots first, name it afterwards.
    ///
    /// In the navigation bar, because the trailing end of the tab bar is the system's search
    /// button and nothing can take its place there.
    private var addButton: some View {
        Button("Mark a plot on the map", systemImage: "plus") {
            selection = nil
            outline = Outline()
        }
        .labelStyle(.iconOnly)
    }

    /// Says the land was filed, for as long as it takes to read. It goes on its own, because
    /// the card underneath it is the thing to look at.
    @ViewBuilder
    private var filedBanner: some View {
        if filedNotice {
            Label("Plot is Created", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.green, in: .capsule)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation(.snappy) { filedNotice = false }
                }
        }
    }

    @ViewBuilder
    private var problemBanner: some View {
        if let problem = store.problem {
            Label(problem, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: .capsule)
                .padding(.horizontal, 24)
                .padding(.top, 8)
        }
    }
}

#Preview {
    @Previewable @State var camera = MapCameraPosition.automatic
    FieldHelperHomeView(camera: $camera)
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
