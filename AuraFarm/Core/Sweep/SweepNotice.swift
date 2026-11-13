import Foundation

/// Something the app noticed about a saved sweep and the helper has not been told.
///
/// Worked out from what is already on disk rather than kept anywhere: a sweep knows whether
/// its frames joined, whether it stopped on the size ceiling and whether anything counted
/// it, so the list is a reading of the store and never goes stale against it.
///
/// Nothing here is a push notification. The phone is in the helper's hand while a sweep
/// runs, so there is nothing to interrupt them about; these are waiting when they look.
struct SweepNotice: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case storeNearlyFull
        case framesDidNotJoin
        case stoppedEarly
        case notCounted
    }

    var kind: Kind
    var title: String
    var detail: String
    /// The sweep it is about, so tapping it opens that sweep. nil for the store itself.
    var sweep: SavedSweep?

    var id: String { "\(kind.rawValue)|\(sweep?.name ?? "store")" }

    var systemImage: String {
        switch kind {
        case .storeNearlyFull: "externaldrive.badge.exclamationmark"
        case .framesDidNotJoin: "squares.leading.rectangle"
        case .stoppedEarly: "exclamationmark.triangle"
        case .notCounted: "questionmark.circle"
        }
    }

    /// The share of the store that has to be used before it is worth mentioning.
    ///
    /// Not calibrated: at four fifths there is still room for a sweep or two, which is the
    /// point of saying it then rather than when the next one fails.
    static let storeFullShare = 0.8

    /// Everything worth telling the helper, the store first and then the sweeps newest
    /// first, as `SweepLibrary` hands them over.
    static func all(
        for sweeps: [SavedSweep],
        limit: Int64 = SweepLibrary.storeByteLimit
    ) -> [SweepNotice] {
        var notices: [SweepNotice] = []

        let used = sweeps.reduce(into: Int64(0)) { $0 += $1.byteCount }
        if limit > 0, Double(used) >= Double(limit) * storeFullShare {
            notices.append(
                SweepNotice(
                    kind: .storeNearlyFull,
                    title: "The store is nearly full",
                    detail:
                        "\(used.formatted(.byteCount(style: .file))) of "
                        + "\(limit.formatted(.byteCount(style: .file))) used. Copy the tests you "
                        + "have finished with off the phone, or a sweep will stop part-way through.",
                    sweep: nil
                ))
        }

        for sweep in sweeps {
            guard let manifest = sweep.manifest else { continue }
            if let problem = manifest.panoramaProblem {
                notices.append(
                    SweepNotice(
                        kind: .framesDidNotJoin,
                        title: "\(name(of: sweep)): frames did not all join",
                        detail: problem,
                        sweep: sweep
                    ))
            }
            if manifest.stoppedEarly {
                notices.append(
                    SweepNotice(
                        kind: .stoppedEarly,
                        title: "\(name(of: sweep)): stopped early",
                        detail:
                            "It reached the size ceiling with \(manifest.frameCount) frames saved, "
                            + "so it covered less of the slide than a full sweep.",
                        sweep: sweep
                    ))
            }
            if manifest.organismCounts == nil {
                notices.append(
                    SweepNotice(
                        kind: .notCounted,
                        title: "\(name(of: sweep)): nothing counted it",
                        detail:
                            "The frames were kept but the detector did not run, so this sweep has "
                            + "no counts to report.",
                        sweep: sweep
                    ))
            }
        }
        return notices
    }

    private static func name(of sweep: SavedSweep) -> String {
        let typed = sweep.manifest?.details.sampleID.trimmingCharacters(in: .whitespaces) ?? ""
        return typed.isEmpty ? sweep.name : typed
    }
}
