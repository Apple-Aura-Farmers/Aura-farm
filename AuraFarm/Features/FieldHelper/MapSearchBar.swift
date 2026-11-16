import MapKit
import SwiftUI

/// The field along the top of the plots map: somewhere to type a farmer, a plot or a place.
///
/// What is already on the phone comes first, because that is what the helper is usually
/// looking for and it answers without the network. Places come from Apple's own search
/// underneath, for finding a village before any land there has been marked.
struct MapSearchBar: View {
    let farms: [Farm]
    /// Where the map should go, once something is picked.
    var onPick: (MKCoordinateRegion) -> Void

    @State private var query = ""
    @State private var places: [MKMapItem] = []
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 8) {
            field
            if typing, !trimmed.isEmpty {
                results
            }
        }
        .padding(.horizontal, 12)
        .animation(.snappy, value: typing)
        .animation(.snappy, value: matchingFarms.map(\.id))
        .animation(.snappy, value: places.count)
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search Map", text: $query)
                .focused($typing)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                    places = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear the search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassCapsule()
    }

    private var results: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(matchingFarms) { farm in
                    row(farm.farmerName, farm.locationLine, "leaf") {
                        if let region = LandGeometry.region(fitting: farm.allCorners) {
                            pick(region)
                        }
                    }
                }
                ForEach(places, id: \.self) { place in
                    row(place.name ?? "Somewhere", place.placemark.title ?? "", "mappin") {
                        pick(
                            MKCoordinateRegion(
                                center: place.placemark.coordinate,
                                latitudinalMeters: 800, longitudinalMeters: 800))
                    }
                }
                if matchingFarms.isEmpty && places.isEmpty {
                    Text("Nothing found for “\(trimmed)”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
        }
        .frame(maxHeight: 280)
        .glassPanel()
        // Apple's own lookup, once the typing settles.
        .task(id: trimmed) { await lookUpPlaces() }
    }

    private func row(
        _ title: String, _ subtitle: String, _ symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .frame(width: 24)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var trimmed: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Only farms with land, since there is nowhere to send the map for the others.
    private var matchingFarms: [Farm] {
        farms.matching(trimmed).filter { !$0.allCorners.isEmpty }
    }

    private func pick(_ region: MKCoordinateRegion) {
        typing = false
        query = ""
        places = []
        onPick(region)
    }

    private func lookUpPlaces() async {
        guard !trimmed.isEmpty else {
            places = []
            return
        }
        // A pause, so a search is not sent for every letter.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        let found = try? await MKLocalSearch(request: request).start()
        guard !Task.isCancelled else { return }
        places = Array((found?.mapItems ?? []).prefix(8))
    }
}

extension View {
    /// Liquid Glass where the system has it (iOS 26), frosted material before that.
    @ViewBuilder
    fileprivate func glassCapsule() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.regularMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    fileprivate func glassPanel() -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

#Preview {
    MapSearchBar(
        farms: [
            Farm(
                name: "Subak Jatiluwih", farmerName: "Pak Wayan",
                plots: [
                    Plot(
                        name: "Tabanan",
                        corners: [
                            GeoPoint(latitude: -8.4095, longitude: 115.1889),
                            GeoPoint(latitude: -8.4095, longitude: 115.1900),
                            GeoPoint(latitude: -8.4105, longitude: 115.1900),
                        ])
                ])
        ],
        onPick: { _ in }
    )
    .padding(.top, 62)
    .frame(maxHeight: .infinity, alignment: .top)
    .background(.green)
}
