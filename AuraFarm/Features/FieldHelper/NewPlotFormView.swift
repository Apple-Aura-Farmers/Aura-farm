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
    /// Called when the helper taps Edit, to go back to the map with these corners.
    var onEditOutline: (() -> Void)?

    @Environment(FarmStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var farmerName = ""
    @State private var plotName = ""
    @FocusState private var focus: Field?

    private enum Field {
        case farmer, plot
    }

    var body: some View {
        NavigationStack {
            // A Form, so the rows, the grouping and the scroll out from under the keyboard are
            // all the system's. Nothing here draws a field of its own.
            Form {
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
            .animation(.snappy, value: isNameTaken)
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
                    Button("Edit", action: onEditOutline)
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
        if var farm = existingFarm {
            farm.plots.append(plot)
            store.update(farm)
        } else {
            // A farmer nobody has recorded before. The farm is named after them until there is
            // somewhere to ask for a name of its own.
            store.add(
                Farm(
                    name: trimmed(farmerName), farmerName: trimmed(farmerName), plots: [plot]))
        }
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
        onEditOutline: {}
    )
    .environment(
        FarmStore(
            fileURL: nil,
            farms: [
                Farm(name: "Pak Wayan", farmerName: "Pak Wayan", plots: [Plot(name: "Tabanan", corners: [])]),
                Farm(name: "Pak Zayan", farmerName: "Pak Zayan"),
            ]))
}
