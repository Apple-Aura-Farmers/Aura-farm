import SwiftUI

/// File › Import Soil Reports…, for the window in front.
struct ImportCommands: Commands {
    @FocusedValue(\.importSoilReports) private var importSoilReports

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("Import Soil Reports…") {
                importSoilReports?()
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            .disabled(importSoilReports == nil)
        }
    }
}

extension FocusedValues {
    /// Opens the import panel in the focused window.
    var importSoilReports: (() -> Void)? {
        get { self[ImportSoilReportsKey.self] }
        set { self[ImportSoilReportsKey.self] = newValue }
    }

    private struct ImportSoilReportsKey: FocusedValueKey {
        typealias Value = () -> Void
    }
}
