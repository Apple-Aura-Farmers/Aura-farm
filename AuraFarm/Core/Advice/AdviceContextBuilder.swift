import Foundation

/// Works out which organism notes, patterns, actions and cautions apply to one sample.
/// Deterministic: the code decides the facts, and the model only phrases them.
///
/// The rules mirror `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change them in both places.
///
/// PROVISIONAL: not checked by an agronomist.
struct AdviceContextBuilder {
    var thresholds = AdvicePatternThresholds()
    var bands = CountBands()

    static let ciliates: Set<String> = ["paramecium", "vorticella", "coleps", "didinium"]
    static let euglenoids: Set<String> = ["euglena", "phacus", "lepocinclis"]
    static let cleanWaterAlgae: Set<String> = ["dinobryon", "micrasterias"]

    func context(for result: SoilResult, estimate: SoilHealthEstimate, history: [PastResult]) -> AdviceContext
    {
        let (interpreted, alsoSeen) = readings(for: result)
        let signals = Signals(
            result: result, level: estimate.level, interpreted: interpreted, thresholds: thresholds)
        let patterns = AdvicePattern.allCases.filter { signals.matches($0) }
        let actions = suggestedActions(
            signals: signals, patterns: Set(patterns), result: result, level: estimate.level,
            history: history)

        var cautions: [String] = []
        if result.stoppedEarly { cautions.append("The sweep stopped early.") }
        if result.framesKept < thresholds.fewFrames { cautions.append("Only a few frames were kept.") }
        if patterns.contains(.possibleMisidentification) {
            cautions.append("Some organisms may have been misidentified.")
        }

        return AdviceContext(
            result: result, estimate: estimate, interpreted: interpreted, alsoSeen: alsoSeen,
            patterns: patterns, actions: actions, history: history, cautions: cautions)
    }

    // MARK: Readings

    private func readings(
        for result: SoilResult
    ) -> ([AdviceContext.OrganismReading], [AdviceContext.AlsoSeen]) {
        // Merged by note, so "Euglena" and "euglena" in one sweep are one reading.
        var interpretedCounts: [String: (note: OrganismNote, count: Int)] = [:]
        var otherCounts: [String: Int] = [:]
        for (label, count) in result.countsByClass ?? [:] where count > 0 {
            if let note = OrganismNotes.note(forLabel: label), note.use == .interpreted {
                interpretedCounts[note.label, default: (note, 0)].count += count
            } else {
                otherCounts[OrganismNotes.note(forLabel: label)?.displayName ?? label, default: 0] += count
            }
        }

        let frames = Double(max(result.framesKept, 1))
        let interpreted = interpretedCounts.values.compactMap {
            note, count -> AdviceContext.OrganismReading? in
            guard let abundance = note.abundance else { return nil }
            let perFrame = Double(count) / frames
            var band = bands.band(perFrame: perFrame, abundance: abundance)
            if band == .high && count < thresholds.minimumCountForHigh { band = .typical }
            return AdviceContext.OrganismReading(
                note: note, count: count, perFrame: perFrame, band: band,
                lowIsMeaningful: band != .low || result.framesKept >= thresholds.minimumFramesForLow)
        }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.note.displayName < $1.note.displayName }

        let alsoSeen = otherCounts.map { AdviceContext.AlsoSeen(displayName: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.displayName < $1.displayName }
        return (interpreted, alsoSeen)
    }

    // MARK: Actions

    private func suggestedActions(
        signals: Signals, patterns: Set<AdvicePattern>, result: SoilResult,
        level: SoilHealthEstimate.Level, history: [PastResult]
    ) -> [AdviceContext.SuggestedAction] {
        let fairOrPoor = level == .fair || level == .poor
        let recent = Set(result.recentActions)
        let stage = result.cropStage
        var picked: [AdviceAction.ID: (because: String, reason: String)] = [:]
        func add(_ id: AdviceAction.ID, _ because: String, _ reason: String) {
            picked[id] = (because, reason)
        }

        let tooFew = level == .tooFewToSay
        let unreadable = patterns.contains(.nothingInterpretable)
        let mixed = patterns.contains(.mixedSignals)
        let oneKind = patterns.contains(.onlyOneKind)
        let fewFrames = result.framesKept < thresholds.fewFrames
        let freshLabels = [
            tooFew ? "too few to say" : nil,
            result.stoppedEarly ? "sweep stopped early" : nil,
            fewFrames ? "few frames kept" : nil,
            oneKind ? "only one kind found" : nil,
            unreadable ? "nothing that can be read" : nil,
            mixed ? "mixed signals" : nil,
        ].compactMap { $0 }
        if !freshLabels.isEmpty {
            // The reason names the first trigger in this order, which is not the label order.
            let reason =
                tooFew
                ? AdviceReasons.tooFewToSay
                : unreadable
                    ? AdviceReasons.nothingReadable
                    : mixed
                        ? AdviceReasons.mixedSignals
                        : oneKind
                            ? AdviceReasons.onlyOneKind
                            : result.stoppedEarly ? AdviceReasons.stoppedEarly : AdviceReasons.fewFrames
            add(.resampleFresh, freshLabels.joined(separator: ", "), reason)
        }

        if result.moisture == .drained && fairOrPoor {
            add(.resampleFlooded, "drained field", AdviceReasons.drained)
        }
        if fairOrPoor { add(.resampleLater, "\(level.rawValue) result", AdviceReasons.sampleVaries) }
        if patterns.contains(.possibleMisidentification) {
            add(.resampleTrust, "possible misidentification", AdviceReasons.misidentified)
        }
        let concern = patterns.contains { $0.isConcern } || signals.anyEuglenoidHigh
        if level == .good && level != .poor && !concern {
            add(.keepPractice, "good result", AdviceReasons.plentyOfLife)
        }

        let lowReasons = [
            signals.lowAbundance ? "low abundance" : nil,
            signals.lowDiversity ? "low diversity" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        let dominant = patterns.contains(.euglenoidsDominant)
        let enrichedOrClean =
            signals.anyEuglenoidHigh || dominant || patterns.contains(.cleanWaterAlgae)

        if !lowReasons.isEmpty && !enrichedOrClean && stage != .seedling && !recent.contains(.addedStraw) {
            add(
                .returnStraw, lowReasons,
                signals.lowAbundance ? AdviceReasons.strawLowAbundance : AdviceReasons.strawLowDiversity)
        }
        if signals.lowAbundance { add(.stopBurning, "low abundance", AdviceReasons.burning) }
        if signals.lowAbundance && !enrichedOrClean && !recent.contains(.addedCompost) {
            add(.addCompost, "low abundance", AdviceReasons.compost)
        }
        if !lowReasons.isEmpty && ![.seedling, .tillering, .flowering].contains(stage) {
            add(
                .greenManure, lowReasons,
                signals.lowAbundance
                    ? AdviceReasons.coverCropLowAbundance : AdviceReasons.coverCropLowDiversity)
        }

        if dominant {
            add(.refreshWater, "euglenoids dominant", AdviceReasons.stillWater)
        } else if signals.anyEuglenoidHigh {
            add(.refreshWater, "euglenoids high", AdviceReasons.stillWater)
        }
        if dominant && stage != .flowering && result.moisture != .drained && !recent.contains(.drained) {
            add(.alternateWetDry, "euglenoids dominant", AdviceReasons.airInSoil)
        }
        if dominant {
            if recent.contains(.fertilized) {
                add(
                    .reviewFertilizer, "euglenoids dominant, fertilized recently",
                    AdviceReasons.fertilizerAfterFertilizing)
            } else {
                add(.reviewFertilizer, "euglenoids dominant", AdviceReasons.fertilizer)
            }
        }
        if patterns.contains(.nematodesHigh) {
            add(.checkRootPests, "nematodes high", AdviceReasons.rootPests)
        }

        let mustCheck = picked.keys.contains { AdviceActions.action($0)?.review == .must }
        if level == .poor {
            add(.talkExtension, "poor result", AdviceReasons.extensionAfterPoor)
        } else if mustCheck {
            add(.talkExtension, "big changes suggested", AdviceReasons.extensionBeforeBiggerChanges)
        }
        if level == .poor && history.first?.level == .poor {
            add(.labTest, "poor result twice in a row", AdviceReasons.lowTwice)
        }
        add(.keepNotes, "every result", AdviceReasons.notes)

        if patterns.contains(where: \.blocksImprovementActions) {
            let allowed: Set<AdviceAction.ID> = [
                .resampleFresh, .resampleFlooded, .resampleLater, .resampleTrust, .keepNotes,
            ]
            picked = picked.filter { allowed.contains($0.key) }
        }

        return AdviceAction.ID.allCases.compactMap { id in
            guard let entry = picked[id], let action = AdviceActions.action(id) else { return nil }
            return AdviceContext.SuggestedAction(action: action, because: entry.because, reason: entry.reason)
        }
    }
}

/// The counts a sample's patterns and actions are read from.
private struct Signals {
    let result: SoilResult
    let level: SoilHealthEstimate.Level
    let interpreted: [AdviceContext.OrganismReading]
    let thresholds: AdvicePatternThresholds

    var interpretedTotal: Int { interpreted.reduce(0) { $0 + $1.count } }

    var allTotal: Int { (result.countsByClass ?? [:]).values.filter { $0 > 0 }.reduce(0, +) }

    var trustCheckTotal: Int {
        (result.countsByClass ?? [:])
            .filter { $0.value > 0 && OrganismNotes.note(forLabel: $0.key)?.use == .trustCheck }
            .values.reduce(0, +)
    }

    func count(of labels: Set<String>) -> Int {
        interpreted.filter { labels.contains($0.note.label) }.reduce(0) { $0 + $1.count }
    }

    /// The share of the interpreted total, from 0 to 1.
    func share(of labels: Set<String>) -> Double {
        interpretedTotal > 0 ? Double(count(of: labels)) / Double(interpretedTotal) : 0
    }

    /// nil when the organism was not counted.
    func band(_ label: String) -> CountBands.Band? {
        interpreted.first { $0.note.label == label }?.band
    }

    var anyEuglenoidHigh: Bool {
        interpreted.contains { AdviceContextBuilder.euglenoids.contains($0.note.label) && $0.band == .high }
    }

    var cleanWaterAlgaCounted: Bool { count(of: AdviceContextBuilder.cleanWaterAlgae) > 0 }

    /// False when nothing interpreted was counted: nothing readable is not low abundance.
    var lowAbundance: Bool {
        interpretedTotal > 0
            && Double(interpretedTotal) / Double(max(result.framesKept, 1)) < thresholds.lowAbundancePerFrame
    }

    /// False when nothing interpreted was counted: nothing readable is not low diversity.
    var lowDiversity: Bool { interpretedTotal > 0 && interpreted.count <= thresholds.lowDiversityKinds }

    func matches(_ pattern: AdvicePattern) -> Bool {
        switch pattern {
        case .severalRoles:
            let roles = Set(interpreted.compactMap(\.note.role))
            return roles.contains(.bacteriaFeeder) && roles.contains(.predator)
                && (roles.contains(.alga) || roles.contains(.lightAndDissolved))
        case .euglenoidsDominant:
            return interpretedTotal > 0 && !matches(.mixedSignals)
                && share(of: AdviceContextBuilder.euglenoids) >= thresholds.euglenoidsDominantShare
                && share(of: AdviceContextBuilder.ciliates) < thresholds.fewCiliatesShare
        case .cleanWaterAlgae:
            return cleanWaterAlgaCounted && !matches(.mixedSignals)
                && share(of: AdviceContextBuilder.euglenoids) < thresholds.cleanWaterEuglenoidShare
        case .mixedSignals:
            return anyEuglenoidHigh && cleanWaterAlgaCounted
        case .predatorWithLowPrey:
            let prey = band("paramecium")
            return band("didinium") != nil && (prey == nil || prey == .low)
        case .plentyOfVorticella:
            return band("vorticella") == .high
        case .plentyOfTestateAmoebae:
            return band("arcellinida") == .high
        case .nematodesHigh:
            return band("nematode") == .high
        case .drainedLowCounts:
            return result.moisture == .drained && (level == .fair || level == .poor)
        case .onlyOneKind:
            return interpreted.count == 1
        case .nothingInterpretable:
            return allTotal > 0 && interpretedTotal == 0
        case .possibleMisidentification:
            return allTotal > 0
                && Double(trustCheckTotal) / Double(allTotal) >= thresholds.misidentificationShare
        }
    }
}
