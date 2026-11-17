import CoreML
import Foundation

/// Which hardware the live-count model runs on. The Neural Engine is chosen for power per
/// inference, not speed (on a Mac the graphics chip took 10 ms and the Neural Engine 16.7 ms);
/// the two gave the same detections on 103 frames apart from two right at the 0.3 cut-off.
enum DetectorUnits: String, CaseIterable, Identifiable {
    case neuralEngine = "ne"
    case graphics = "gpu"

    var id: String { rawValue }

    var computeUnits: MLComputeUnits {
        switch self {
        case .neuralEngine: .cpuAndNeuralEngine
        case .graphics: .cpuAndGPU
        }
    }

    var displayName: String {
        switch self {
        case .neuralEngine: "Neural Engine"
        case .graphics: "Graphics"
        }
    }
}
