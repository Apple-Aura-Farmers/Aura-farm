import SwiftUI

extension View {
    /// Where a tap on a farm, a field or a soil test goes, for any navigation stack that
    /// shows farm records. Each stack's root view applies it once.
    func farmRecordDestinations() -> some View {
        self
            .navigationDestination(for: Farm.self) { farm in
                FarmDetailView(farm: farm)
            }
            .navigationDestination(for: Field.self) { field in
                FieldDetailView(field: field)
            }
            .navigationDestination(for: SoilTest.self) { test in
                SoilTestDetailView(test: test)
            }
    }
}
