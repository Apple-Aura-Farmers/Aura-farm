import SwiftData
import SwiftUI

/// The program manager's screens: the farms and everything about them, the tests waiting to
/// be filed, and every test taken.
struct ManagerHomeView: View {
    @Query private var soilTests: [SoilTest]

    var body: some View {
        TabView {
            NavigationStack {
                FarmListView()
                    .farmRecordDestinations()
            }
            .tabItem { Label("Farms", systemImage: "leaf") }

            NavigationStack {
                SoilTestListView(scope: .inbox)
                    .farmRecordDestinations()
            }
            .tabItem { Label("Inbox", systemImage: "tray") }
            .badge(inboxCount)

            NavigationStack {
                SoilTestListView(scope: .all)
                    .farmRecordDestinations()
            }
            .tabItem { Label("All Tests", systemImage: "testtube.2") }
        }
    }

    /// Tests not yet filed under a field. Zero shows no badge.
    private var inboxCount: Int {
        soilTests.filter { $0.field == nil }.count
    }
}
