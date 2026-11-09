import SwiftData
import SwiftUI

@main
struct AuraFarmApp: App {
    /// The farm records both roles share on this phone.
    private let container: ModelContainer

    init() {
        do {
            container = try FarmStore.makeContainer()
        } catch {
            // Without its store the app has nothing to file results in. This is a damaged or
            // unreadable store, not a state anyone can recover from in the app.
            fatalError("The farm records could not be opened: \(error)")
        }

        #if DEBUG
            // Launched with -benchmarkDetector, the app times the detector and prints the
            // result instead of waiting to be tapped. That is the only way to read the
            // numbers off a phone over a cable.
            if ProcessInfo.processInfo.arguments.contains("-benchmarkDetector") {
                Task.detached(priority: .userInitiated) { DetectorBenchmark.printEveryHardware() }
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RoleRootView()
        }
        .modelContainer(container)
    }
}
