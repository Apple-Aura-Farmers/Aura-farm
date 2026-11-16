import Foundation

/// Says when the lab should save a frame for tuning: the moments edges are decided or nearly
/// decided. Pure; the caller feeds it every logged guide row and decides rate and count limits.
struct SnapshotTrigger {
    /// Edge reasons worth a frame when they first show.
    static let reasons: Set<String> = [
        "side_imbalance", "corner", "corner_rejected", "halves_too_close", "vouched",
    ]

    private var reason = ""
    private var verdict = ""
    private var instruction = ""
    private var lineCandidate = false

    /// - Parameter lineCandidate: whether the edge-line detector found a candidate; nil on a
    ///   frame it did not run on (the last answer stands).
    mutating func update(
        edgeReason: String, edgeVerdict: String, instruction now: String, lineCandidate now2: Bool?
    ) -> Bool {
        var fire = false
        if edgeReason != reason, Self.reasons.contains(edgeReason) { fire = true }
        if let now2 {
            if now2 && !lineCandidate { fire = true }
            lineCandidate = now2
        }
        if now != instruction, now == "check_edge" { fire = true }
        if edgeVerdict != verdict, edgeVerdict == "confirmed" { fire = true }
        reason = edgeReason
        verdict = edgeVerdict
        instruction = now
        return fire
    }

    mutating func reset() { self = SnapshotTrigger() }
}
