import SwiftUI

@main
struct MicroscopeCounterApp: App {
    init() {
        #if DEBUG
            // Launched with -benchmarkDetector, the app times the detector and prints the
            // result instead of waiting to be tapped. That is the only way to read the
            // numbers off a phone over a cable.
            if ProcessInfo.processInfo.arguments.contains("-benchmarkDetector") {
                Task.detached(priority: .userInitiated) { DetectorBench.printEveryHardware() }
            }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            SampleSetupView()
        }
    }
}
