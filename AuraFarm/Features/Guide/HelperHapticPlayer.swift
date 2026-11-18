import UIKit

/// Plays a `HelperHaptic`: its taps, with the delays the pattern says. One at a time: a new
/// pattern cancels the one still playing.
@MainActor
final class HelperHapticPlayer {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let firm = UIImpactFeedbackGenerator(style: .heavy)
    private let success = UINotificationFeedbackGenerator()
    private var task: Task<Void, Never>?

    func play(_ haptic: HelperHaptic) {
        task?.cancel()
        let taps = haptic.taps
        guard !taps.isEmpty else { return }
        task = Task { [weak self] in
            var elapsed = 0.0
            for tap in taps {
                let wait = tap.delay - elapsed
                if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
                guard !Task.isCancelled, let self else { return }
                elapsed = tap.delay
                switch tap.kind {
                case .light: self.light.impactOccurred()
                case .firm: self.firm.impactOccurred()
                case .success: self.success.notificationOccurred(.success)
                }
            }
        }
    }

    /// The spot ticked: one light tap, as the lab does.
    func spotTicked() { play(.oneLight) }
}
