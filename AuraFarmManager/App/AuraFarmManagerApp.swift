import SwiftData
import SwiftUI

/// The farm manager: soil tests sent from the field app, filed by farm and field.
@main
@MainActor
struct AuraFarmManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var importCoordinator: SoilReportImportCoordinator

    private let container: ModelContainer

    init() {
        let container: ModelContainer
        do {
            container = try FarmStore.makeContainer()
        } catch {
            // Without its store the app has nothing to show or keep. This is a damaged or
            // unreadable store, not a state a user can recover from in the app.
            fatalError("The farm records could not be opened: \(error)")
        }
        self.container = container
        _importCoordinator = State(initialValue: SoilReportImportCoordinator(context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(importCoordinator)
                .onAppear {
                    appDelegate.openHandler = { [importCoordinator] urls in
                        importCoordinator.importFiles(at: urls)
                    }
                }
        }
        .modelContainer(container)
        .commands {
            ImportCommands()
        }
    }
}
