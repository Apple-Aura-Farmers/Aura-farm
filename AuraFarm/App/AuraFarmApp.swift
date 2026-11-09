import SwiftUI

@main
struct AuraFarmApp: App {
    init() {
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
            #if DEBUG
                // Launched with -resultScenario good (or any ResultScenario name), the app opens
                // straight on that result state, for screenshots without tapping through.
                if let scenario = Self.launchScenario {
                    NavigationStack { ResultScenarioScreen(scenario: scenario, useLiveModel: false) }
                } else {
                    SampleSetupView()
                }
            #else
                SampleSetupView()
            #endif
        }
    }

    #if DEBUG
        private static var launchScenario: ResultScenario? {
            UserDefaults.standard.string(forKey: "resultScenario").flatMap(ResultScenario.init(rawValue:))
        }
    #endif
}
