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
            VStack(alignment: .leading, spacing: 16) {
                farmerField
                plotField
                preview
                Spacer(minLength: 0)
                doneButton
            }
            .padding(20)
            .navigationTitle("New Plot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
        }
    }

    // MARK: The farmer

    private var farmerField: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Farmer's name", text: $farmerName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .farmer)
                    .submitLabel(.next)
                    .onSubmit { focus = .plot }
                Image(systemName: "chevron.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))

            // Only while the field is being typed in, so the suggestions do not sit over the
            // plot name once the farmer has been chosen.
            if focus == .farmer, !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(suggestions.enumerated()), id: \.element) { index, name in
                        if index > 0 { Divider() }
                        Button {
                            farmerName = name
                            focus = .plot
                        } label: {
                            Text(name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding(.top, 4)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.15), value: suggestions)
    }

    /// Farmers already on the phone whose name contains what has been typed. Everything, while
    /// nothing has been.
    private var suggestions: [String] {
        let typed = trimmed(farmerName)
        let names = Set(store.farms.map(\.farmerName))
        return
            names
            .filter { typed.isEmpty || ($0.localizedStandardContains(typed) && $0 != typed) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: The plot

    private var plotField: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Plot's name", text: $plotName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($focus, equals: .plot)
                .padding(16)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    if isNameTaken {
                        RoundedRectangle(cornerRadius: 14).stroke(.red, lineWidth: 1)
                    }
                }
            if isNameTaken {
                Text("This name is taken")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var isNameTaken: Bool {
        existingFarm?.hasPlot(named: plotName) ?? false
    }

    // MARK: The land

    private var preview: some View {
        LandMapView(corners: corners)
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(alignment: .topTrailing) {
                if let onEditOutline {
                    Button("Edit") { onEditOutline() }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(.blue, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(10)
                }
            }
    }

    private var doneButton: some View {
        Button(action: save) {
            Text("Done")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canSave)
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
