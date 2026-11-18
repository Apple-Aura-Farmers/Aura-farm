import SwiftUI

/// Naming a plot once its edge has been walked: whose it is, what it is called, and a last
/// look at the shape.
///
/// The farmer comes first because it decides everything else: the colour the land is drawn
/// in, which plots the name has to be different from, and whether this starts a new farmer or
/// adds to one already known. Typing suggests the farmers already on the phone rather than
/// making the helper remember how a name was spelled last time.
struct NewPlotFormView: View {
    /// The outline just marked.
    let corners: [GeoPoint]
    /// Called with the farm this plot was filed against and the plot itself, so whatever opened
    /// the form can show the land it has just taken in.
    var onSaved: ((Farm, Plot) -> Void)?
    /// Called when the helper taps Edit, to go back to the map with these corners. It is handed
    /// what has been typed so far, so the form they come back to still holds it.
    var onEditOutline: ((_ farmer: String, _ plot: String) -> Void)?

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var farmerName: String
    @State private var plotName: String
    @FocusState private var focus: Field?

    init(
        corners: [GeoPoint], farmer: String = "", plot: String = "",
        onSaved: ((Farm, Plot) -> Void)? = nil,
        onEditOutline: ((String, String) -> Void)? = nil
    ) {
        self.corners = corners
        self.onSaved = onSaved
        self.onEditOutline = onEditOutline
        _farmerName = State(initialValue: farmer)
        _plotName = State(initialValue: plot)
    }

    private enum Field {
        case farmer, plot
    }

    var body: some View {
        NavigationStack {
            // A Form, so the rows, the grouping and the scroll out from under the keyboard are
            // all the system's. Nothing here draws a field of its own.
            Form {
                Group {
                    Section("Farmer") {
                        TextField("Farmer's name", text: $farmerName)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .farmer)
                            .submitLabel(.next)
                            .onSubmit { focus = .plot }

                        // A Picker rather than a list under the field: the control iOS already has
                        // for choosing one of a few things, so it opens, scrolls and closes itself.
                        if !known.isEmpty {
                            Picker("Already on this phone", selection: $farmerName) {
                                ForEach(known, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                        }
                    }

                    Section {
                        TextField("Plot's name", text: $plotName)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .plot)
                    } header: {
                        Text("Plot")
                    } footer: {
                        // The Form's own footer, which makes room for itself as it appears.
                        if isNameTaken {
                            Text("\(trimmed(farmerName)) already has a plot called that.")
                                .foregroundStyle(.red)
                        }
                    }

                    Section("The land") { preview }
                }
                .listRowBackground(Color.auraRow)
            }
            .animation(.snappy, value: isNameTaken)
            .auraBackground()
            .navigationTitle("New Plot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // In the bar, so the keyboard can never cover the way out of the form.
                    Button("Done", action: save).disabled(!canSave)
                }
            }
        }
    }

    // MARK: The farmer

    /// Every farmer the phone knows, for the picker.
    private var known: [String] {
        Set(store.farms.map(\.farmerName))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var isNameTaken: Bool {
        existingFarm?.hasPlot(named: plotName) ?? false
    }

    // MARK: The land

    private var preview: some View {
        LandMapView(corners: corners)
            .frame(height: 180)
            .listRowInsets(EdgeInsets())
            .overlay(alignment: .topTrailing) {
                if let onEditOutline {
                    Button("Edit") { onEditOutline(farmerName, plotName) }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.capsule)
                        .padding(10)
                }
            }
    }

    // MARK: Saving

    /// The farm this plot joins, if the helper named a farmer already on the phone.
    private var existingFarm: Farm? {
        let typed = trimmed(farmerName)
        return store.farms.first {
            $0.farmerName.caseInsensitiveCompare(typed) == .orderedSame
        }
    }

    private var canSave: Bool {
        !trimmed(farmerName).isEmpty && !trimmed(plotName).isEmpty && !isNameTaken
            && corners.count >= PlotBoundary.fewestCorners
    }

    private func save() {
        guard canSave else { return }
        let plot = Plot(name: trimmed(plotName), corners: corners)
        let farm: Farm
        if var existing = existingFarm {
            existing.plots.append(plot)
            store.update(existing)
            farm = existing
        } else {
            // A farmer nobody has recorded before. The farm is named after them until there is
            // somewhere to ask for a name of its own.
            farm = Farm(
                name: trimmed(farmerName), farmerName: trimmed(farmerName), plots: [plot])
            store.add(farm)
        }
        store.publish(farm)
        onSaved?(farm, plot)
        dismiss()
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    NewPlotFormView(
        corners: [
            GeoPoint(latitude: -8.4095, longitude: 115.1889),
            GeoPoint(latitude: -8.4095, longitude: 115.1900),
            GeoPoint(latitude: -8.4105, longitude: 115.1900),
        ],
        onEditOutline: { _, _ in }
    )
    .environment(
        FarmStore(
            fileURL: nil,
            farms: [
                Farm(name: "Pak Wayan", farmerName: "Pak Wayan", plots: [Plot(name: "Tabanan", corners: [])]),
                Farm(name: "Pak Zayan", farmerName: "Pak Zayan"),
            ]))
}
