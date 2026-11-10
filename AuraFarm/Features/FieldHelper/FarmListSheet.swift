import SwiftUI

/// The list of farms that slides up over the home map. It has no navigation of its own: tapping
/// a farm or the add button hands the choice back to the home screen, which closes this sheet
/// first and then opens the page or the form.
struct FarmListSheet: View {
    let farms: [Farm]
    let onOpen: (Farm) -> Void
    let onAdd: () -> Void

    @Environment(FarmStore.self) private var store
    /// The farm waiting on a yes to being deleted.
    @State private var farmToDelete: Farm?

    /// Below this height the sheet is just a bar, and shows only the title row.
    private static let barHeight: CGFloat = 150
    /// Room taken by the drag handle at the top edge of the sheet.
    private static let handleClearance: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let isBar = proxy.size.height < Self.barHeight
            VStack(spacing: 0) {
                header(isBar: isBar)
                    // As a bar, the row takes all the height there is and centres itself in
                    // it, so it sits in the middle however tall the system makes the bar.
                    .frame(maxHeight: isBar ? .infinity : nil)
                if !isBar {
                    farmList
                }
            }
        }
        .background(.ultraThinMaterial)
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

    private func header(isBar: Bool) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("My farms")
                    .font(.title3.bold())
                Text("^[\(farms.count) farm](inflect: true)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Add a farm")
        }
        .padding(.top, Self.handleClearance)
        .padding(.horizontal, 20)
        // No space below as a bar, so the row is centred in what is left under the handle.
        .padding(.bottom, isBar ? 0 : 10)
    }

    private var farmList: some View {
        List {
            ForEach(farms) { farm in
                Button {
                    onOpen(farm)
                } label: {
                    row(for: farm)
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.primary.opacity(0.08))
                        .padding(.vertical, 2)
                )
                .swipeActions {
                    Button(role: .destructive) {
                        farmToDelete = farm
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .padding()
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        // Room under the last card, so it can be scrolled clear of the rounded corners.
        .contentMargins(.bottom, 28, for: .scrollContent)
        // Lets the list run to the bottom edge of the sheet. Left alone, it stops at the home
        // indicator and leaves an empty strip under the cards.
        .ignoresSafeArea(.container, edges: .bottom)
    }

    private func row(for farm: Farm) -> some View {
        HStack(spacing: 14) {
            FarmOutlineThumbnail(corners: farm.corners)
            VStack(alignment: .leading, spacing: 2) {
                Text(farm.farmerName)
                    .font(.headline)
                if let area = farm.areaSquareMetres {
                    Text(LandGeometry.hectaresDescription(squareMetres: area))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

#Preview {
    FarmListSheet(
        farms: [
            Farm(
                farmerName: "Pak Wayan",
                corners: [
                    GeoPoint(latitude: -8.4095, longitude: 115.1889),
                    GeoPoint(latitude: -8.4095, longitude: 115.1900),
                    GeoPoint(latitude: -8.4105, longitude: 115.1896),
                    GeoPoint(latitude: -8.4105, longitude: 115.1889),
                ])
        ],
        onOpen: { _ in },
        onAdd: {}
    )
    .environment(FarmStore(fileURL: nil))
}
