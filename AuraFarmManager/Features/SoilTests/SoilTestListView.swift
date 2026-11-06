import SwiftData
import SwiftUI

/// The inbox, or every soil test, newest first.
struct SoilTestListView: View {
    enum Scope {
        /// Tests not yet filed under a field.
        case inbox
        case all
    }

    let scope: Scope
    @Binding var selection: PersistentIdentifier?

    @Query(sort: \SoilTest.recordedAt, order: .reverse) private var allTests: [SoilTest]

    var body: some View {
        Group {
            if visibleTests.isEmpty {
                ContentUnavailableView {
                    Label(scope == .inbox ? "Inbox Is Empty" : "No Soil Tests Yet", systemImage: "tray")
                } description: {
                    Text(emptyDescription)
                }
            } else {
                SoilTestTable(tests: visibleTests, selection: $selection)
            }
        }
        .navigationTitle(scope == .inbox ? "Inbox" : "All Tests")
        .navigationSubtitle(subtitle)
    }

    private var visibleTests: [SoilTest] {
        switch scope {
        case .inbox: return allTests.filter { $0.field == nil }
        case .all: return allTests
        }
    }

    private var subtitle: String {
        visibleTests.count == 1 ? "1 soil test" : "\(visibleTests.count) soil tests"
    }

    private var emptyDescription: String {
        switch scope {
        case .inbox:
            return """
                On the iPhone, open a saved sweep in Aura Farm and choose Send to Mac. Open the \
                .aurafarm file here, drag it into this window, or choose File › Import Soil Reports.
                """
        case .all:
            return "Soil tests sent from the iPhone appear here once they are imported."
        }
    }
}
