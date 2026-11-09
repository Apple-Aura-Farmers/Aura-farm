import SwiftUI

/// How many organisms were counted, opening out to which kinds and how many of each.
///
/// Takes plain values and bindings only, so a new design can replace it without touching
/// how the rows are worked out.
struct OrganismCountSection: View {
    /// nil when the sweep was not counted.
    let total: Int?
    let rows: [TaxonCount]
    @Binding var taxonomy: OrganismTaxonomy
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            if let total {
                DisclosureGroup(isExpanded: $isExpanded) {
                    Picker("Names", selection: $taxonomy) {
                        ForEach(OrganismTaxonomy.allCases) { taxonomy in
                            Text(taxonomy.title).tag(taxonomy)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.vertical, 4)

                    if rows.isEmpty {
                        Text("Nothing was counted.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rows) { row in
                            LabeledContent {
                                Text(row.count, format: .number)
                                    .font(.body.monospacedDigit().bold())
                            } label: {
                                Text(row.name)
                                if let label = row.label, label != row.name {
                                    Text(label).italic()
                                }
                            }
                        }
                    }
                } label: {
                    LabeledContent {
                        Text(total, format: .number)
                            .font(.title2.monospacedDigit().bold())
                            .foregroundStyle(.primary)
                    } label: {
                        Text("Microbes found")
                        Text(isExpanded ? "Hide the breakdown" : "Tap to see each kind")
                    }
                }
            } else {
                Text("This sweep was not counted: the detector could not open.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Counted")
        } footer: {
            if taxonomy == .organismGroup, isExpanded {
                Text(
                    "Organism groups are matched to the model's classes provisionally, for the "
                        + "team to confirm."
                )
            }
        }
    }
}

#Preview {
    @Previewable @State var taxonomy = OrganismTaxonomy.modelClass
    @Previewable @State var expanded = true
    let counts = ["paramecium": 12, "euglena": 4, "vorticella": 2]
    List {
        OrganismCountSection(
            total: 18,
            rows: taxonomy.rows(from: counts),
            taxonomy: $taxonomy,
            isExpanded: $expanded
        )
    }
}
