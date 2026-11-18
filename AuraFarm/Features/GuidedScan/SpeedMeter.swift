import SwiftUI

/// The speed bar the page and the lab share: the lab's own, moved here so there is one copy.
struct LiveSpeedMeter: View {
    var model: ScanEngine
    var body: some View {
        SpeedMeter(
            speedFraction: model.speedState.speedFraction,
            touchMarker: model.guideDryRun && model.spotMode == .briefTouch
                ? BriefTouchThresholds().maxTouchSpeedFraction : nil)
    }
}

/// A bar with green, orange and red zones and a needle. The scale ends at twice the
/// too-fast speed. `touchMarker` (brief-touch mode) marks the fastest speed that still counts
/// as touching a spot.
struct SpeedMeter: View {
    var speedFraction: Double
    var thresholds = MovementIndicatorThresholds()
    var touchMarker: Double?

    var body: some View {
        let end = thresholds.tooFastSpeedFraction * 2
        let comfortable = min(thresholds.comfortableSpeedFraction / end, 1)
        let tooFast = min(thresholds.tooFastSpeedFraction / end, 1)
        let needle = min(max(speedFraction / end, 0), 1)
        VStack(alignment: .leading, spacing: 2) {
            Text("Speed").font(.caption2.bold()).foregroundStyle(.white)
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().fill(.green).frame(width: width * comfortable)
                        Rectangle().fill(.orange).frame(width: width * (tooFast - comfortable))
                        Rectangle().fill(.red)
                    }
                    .clipShape(Capsule())
                    if let touchMarker {
                        Rectangle().fill(.black.opacity(0.85))
                            .frame(width: 3, height: 22)
                            .offset(x: width * min(max(touchMarker / end, 0), 1) - 1.5)
                    }
                    Rectangle().fill(.white)
                        .frame(width: 4, height: 22)
                        .shadow(radius: 1)
                        .offset(x: width * needle - 2)
                }
            }
            .frame(height: 22)
        }
        .padding(8)
        .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
