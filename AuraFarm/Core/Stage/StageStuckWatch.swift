import Foundation

/// Spots a gear that does not answer: the picture barely moved for a move that should have
/// moved it. After a few in a row on one servo its step is made bigger until it moves again.
/// Pure: the caller says what each settled move did.
struct StageStuckWatch {
    /// Under this share of the expected travel is "no response".
    var noResponseShare = 0.25
    /// At least this share of the expected travel is "moved".
    var movedShare = 0.5
    /// A move expected to travel less than this (fields) says nothing.
    var minExpectedFields = 0.1
    var noResponseToBoost = 3
    var boostedMovesToGiveUp = 5
    /// Degrees added to the step while boosted.
    var boostDegrees = 2

    enum BoostOffReason: String, Equatable {
        case moved
        case gaveUp = "gave_up"
    }

    struct Outcome: Equatable {
        var judged = false
        var noResponse = false
        var boostOn = false
        var boostOff: BoostOffReason?
    }

    private struct State {
        var misses = 0
        var boosted = false
        var boostedMisses = 0
    }
    private var states: [StageAxis: State] = [:]

    /// Degrees to add to this servo's step now: 0, or `boostDegrees` while boosted.
    func extraDegrees(for servo: StageAxis) -> Int {
        states[servo]?.boosted == true ? boostDegrees : 0
    }

    /// - Parameters:
    ///   - seen: how far the picture travelled, in fields.
    ///   - expected: the live fields per degree of the servo times the degrees it moved.
    ///   - detailBefore / detailAfter: the view showed sample or thin while tracking, before and
    ///     after the move. A move without both is not judged.
    mutating func record(
        servo: StageAxis, seen: Double, expected: Double, detailBefore: Bool, detailAfter: Bool
    ) -> Outcome {
        var outcome = Outcome()
        guard detailBefore, detailAfter, expected >= minExpectedFields else { return outcome }
        outcome.judged = true
        var state = states[servo] ?? State()
        if seen < noResponseShare * expected {
            outcome.noResponse = true
            state.misses += 1
            if state.boosted {
                state.boostedMisses += 1
                if state.boostedMisses >= boostedMovesToGiveUp {
                    state = State()
                    outcome.boostOff = .gaveUp
                }
            } else if state.misses >= noResponseToBoost {
                state.boosted = true
                state.boostedMisses = 0
                outcome.boostOn = true
            }
        } else {
            // Any answer breaks the row of misses; only a clear one ends the boost.
            state.misses = 0
            state.boostedMisses = 0
            if state.boosted, seen >= movedShare * expected {
                state = State()
                outcome.boostOff = .moved
            }
        }
        states[servo] = state
        return outcome
    }
}
