import SwiftData
import SwiftUI

/// Picks the field a soil test came from, grouped by farm, or leaves it in the inbox.
struct FieldPicker: View {
    @Binding var selection: Field?

    @Query(sort: \Farm.name) private var farms: [Farm]

    var body: some View {
        Picker("Field", selection: $selection) {
            Text("Inbox, not filed").tag(Field?.none)
            ForEach(farms) { farm in
                Section(farm.name) {
                    ForEach(farm.sortedFields) { field in
                        Text(field.name).tag(Field?.some(field))
                    }
                }
            }
        }
    }

    /// True when there is no field to pick yet.
    static func hasNoFields(_ farms: [Farm]) -> Bool {
        farms.allSatisfy(\.fields.isEmpty)
    }
}
