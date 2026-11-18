import Foundation

/// What the on-device model is told: fixed instructions, and a prompt holding only the parts
/// of the advice content that apply to this sample.
///
/// The model's context window is 4,096 tokens, shared by the instructions, the prompt and
/// the answer, so the prompt never carries the whole catalogue.
///
/// The content mirrors `docs/advice-content.md` (the team's "Advice content, Phase 1",
/// approved 9 November 2026). Change the content in both places.
///
/// PROVISIONAL: not checked by an agronomist.
enum AdvicePromptBuilder {
    /// How much of the context goes into one prompt.
    static let maxOrganisms = 8
    static let maxHistory = 3
    static let maxActions = 6

    static func instructions() -> String {
        let rules = [
            "You help a field helper who visits rice farmers and reads your words aloud to the farmer.",
            "An app counted microorganisms in a drop of paddy soil.",
            "Be calm, practical and encouraging. Never be alarming.",
            "Write in English, with short everyday words and one idea per sentence.",
            "The summary is one sentence, at most about 25 words.",
            "Each action is one sentence, at most about 20 words.",
            "Use only facts in the prompt.",
            "Soil steps come from the helper's soil measurements, not the microscope. Call a measurement low "
                + "or high, not a number, and say it may matter, not that it proves anything.",
            "If a fertilizer kind is given, it is only background. Do not judge it, and do not suggest a "
                + "fertilizer, a product, an amount or a rate.",
            "If you use a farming term such as cover crop or mulch, say plainly what it means.",
            "The rough estimate only reflects how much life was seen. If a pattern raises a concern, do not "
                + "describe the result as good.",
            "Organism notes and patterns only might suggest something. Never treat them as certain.",
            "The summary should cover both the sample and any soil steps listed, in one sentence.",
            "Pick 2 or 3 actions from \"Actions you may suggest\" by their id. Do not invent ids.",
            "For each, write one short sentence on why it fits this sample, building on the reason given. "
                + "Do not repeat the action's wording.",
            "First note 1 or 2 things you noticed, then pick the actions, then write a one-sentence summary.",
            "Do not interpret the \"Also seen\" organisms, and do not mention them at all.",
            "If earlier samples of this plot are given, you may mention a change, but only when the "
                + "moisture state matches.",
        ]
        return (rules + NeverSay.rules).map { "- \($0)" }.joined(separator: "\n")
    }

    static func prompt(for context: AdviceContext) -> String {
        let result = context.result
        var lines: [String] = []

        var sample = ["Sample: \(result.moisture.rawValue)."]
        if let stage = result.cropStage { sample.append("Crop stage: \(stage.label.lowercased()).") }
        sample.append(
            result.isGuidedScan
                ? "Fields of view scanned: \(result.viewsLooked)."
                : "Frames looked at: \(result.framesKept).")
        if !result.recentActions.isEmpty {
            sample.append(
                "Done recently: \(result.recentActions.map { $0.label.lowercased() }.joined(separator: ", "))."
            )
        }
        lines.append(sample.joined(separator: " "))
        lines.append(
            "Rough estimate from the amount of life only: \(words(context.estimate.level)), "
                + "\(context.estimate.confidence.rawValue) confidence.")
        if context.interpretedKinds > 0 {
            lines.append(
                "This sample: \(figures(perFrame: context.interpretedPerFrame, kinds: context.interpretedKinds))."
            )
        }

        if let soil = SoilInputs(result.soil) { lines.append(soilLine(soil)) }

        if !context.cautions.isEmpty { lines.append("Cautions: \(context.cautions.joined(separator: " "))") }

        if !context.interpreted.isEmpty {
            lines.append("Organisms seen:")
            lines += context.interpreted.prefix(maxOrganisms).map(organismLine)
        }

        if !context.alsoSeen.isEmpty {
            let names = context.alsoSeen.map { "\($0.displayName) \($0.count)" }.joined(separator: ", ")
            lines.append("Also seen (do not interpret or mention): \(names).")
        }

        if !context.patterns.isEmpty {
            lines.append("Patterns:")
            lines += context.patterns.map { "- \($0.title): \($0.meaning)" }
        }

        if !context.history.isEmpty {
            lines.append("Earlier samples of this plot:")
            lines += context.history.prefix(maxHistory).map(historyLine)
        }

        let actions = offeredActions(for: context)
        if !actions.isEmpty {
            lines.append("Actions you may suggest:")
            lines += actions.map {
                "- \($0.action.id.rawValue): \"\($0.action.wording)\" "
                    + "(why: \($0.reason); timing: \($0.action.timing.lowercased()))"
            }
        }

        let soilSteps = soilOnlyActions(for: context)
        if !soilSteps.isEmpty {
            lines.append(
                "Soil steps the app will also show (do not pick these; you may mention them in the summary):")
            lines += soilSteps.map { "- \($0.action.wording) (why: \($0.reason))" }
        }

        lines.append("Write the advice.")
        return lines.joined(separator: "\n")
    }

    /// The actions the model may pick: the microscope and general ones. The steps that only the
    /// soil measurements call for are added by `AdviceComposer`, so the model never has to choose
    /// between them and the sample's own steps. The answer is checked against the same list.
    static func offeredActions(for context: AdviceContext) -> [AdviceContext.SuggestedAction] {
        trimmed(context.actions.filter { !($0.fromSoil && !$0.fromMicroscope) }, context: context)
    }

    /// The steps only the soil measurements call for, in priority order, as the report shows them.
    static func soilOnlyActions(for context: AdviceContext) -> [AdviceContext.SuggestedAction] {
        context.actions
            .filter { $0.fromSoil && !$0.fromMicroscope }
            .sorted {
                (AdviceActions.fallbackPriority.firstIndex(of: $0.action.id) ?? Int.max)
                    < (AdviceActions.fallbackPriority.firstIndex(of: $1.action.id) ?? Int.max)
            }
            .prefix(AdviceComposer.maxSoilSteps).map { $0 }
    }

    /// At most `maxActions`, the ones that come first in `AdviceActions.fallbackPriority`, so
    /// keep_notes goes first. Some are never trimmed: the resamples the sample itself calls for,
    /// "sample again" for a fair or poor result, and "talk to your extension officer" when the
    /// result is poor or a must-check action survives. Protected actions count toward the cap; if
    /// they alone ever exceeded it they would all be kept, which today's rules cannot cause. The
    /// result keeps the order it was given.
    static func trimmed(
        _ actions: [AdviceContext.SuggestedAction], context: AdviceContext
    ) -> [AdviceContext.SuggestedAction] {
        guard actions.count > maxActions else { return actions }
        let level = context.estimate.level
        var protected: Set<AdviceAction.ID> = [.resampleFresh, .resampleTrust]
        if level == .fair || level == .poor { protected.insert(.resampleLater) }

        func rank(_ suggested: AdviceContext.SuggestedAction) -> Int {
            AdviceActions.fallbackPriority.firstIndex(of: suggested.action.id) ?? Int.max
        }
        func isMust(_ suggested: AdviceContext.SuggestedAction) -> Bool {
            suggested.action.review == .must
        }
        let room = maxActions - actions.filter { protected.contains($0.action.id) }.count
        var survivors = Array(
            actions.filter { !protected.contains($0.action.id) && $0.action.id != .talkExtension }
                .sorted { rank($0) < rank($1) }
                .prefix(max(room, 0)))

        var kept = protected
        if let extra = actions.first(where: { $0.action.id == .talkExtension }),
            level == .poor || survivors.contains(where: isMust)
        {
            // Make room for it by dropping the least relevant survivor that isn't must-check.
            if survivors.count >= room,
                let drop = survivors.lastIndex(where: { !isMust($0) }) ?? survivors.indices.last
            {
                survivors.remove(at: drop)
            }
            kept.insert(extra.action.id)
        }
        kept.formUnion(survivors.map(\.action.id))
        return actions.filter { kept.contains($0.action.id) }
    }

    private static func organismLine(_ reading: AdviceContext.OrganismReading) -> String {
        let note = reading.note
        let word = reading.band == .low && !reading.lowIsMeaningful ? "few seen" : bandWord(reading.band)
        var line =
            "- \(note.displayName): \(reading.count) (\(String(format: "%.1f", reading.perFrame)) per frame, "
            + "\(word))."
        let silentLows = [OrganismNotes.normal, OrganismNotes.notAConcern]
        switch reading.band {
        case .high:
            if let high = note.highSuggests { line += " Might suggest: \(high)." }
        case .low:
            if reading.lowIsMeaningful, let low = note.lowSuggests, !silentLows.contains(low) {
                line += " Might suggest: \(low)."
            }
        case .typical:
            break
        }
        return line
    }

    /// The measurements the helper recorded, as context for the actions that come from them. They
    /// are not from the microscope, so the line says so. Only the number, its unit and its band go
    /// in: never the standards' guidance. The fertilizer goes in as its kind only, never its amount
    /// or product name, so the model has nothing to repeat as a dose.
    private static func soilLine(_ soil: SoilInputs) -> String {
        let readings = soil.readings.map { reading in
            let amount = number(reading.value)
            let value = reading.unit.isEmpty ? amount : "\(amount) \(reading.unit)"
            return "\(reading.name) \(value) (\(reading.band.label.lowercased()))"
        }
        var line =
            "Soil measurements the helper recorded (not from the microscope): "
            + "\(readings.joined(separator: ", ")). The soil steps listed at the end come from them."
        if soil.ph != nil {
            line += " pH targets for flooded rice are provisional."
            if let water = soil.phFieldWater, water != .notSure {
                line += " The pH was measured on \(water == .drained ? "drained" : "flooded") soil."
            }
        }
        if let kind = soil.fertilizerType, kind.namesAKind {
            line += " Fertilizer kind recorded (background only, not advice): \(kind.label.lowercased())."
        }
        return line
    }

    /// "6.5" or "100", the same on every phone.
    private static func number(_ value: Double) -> String {
        value.formatted(
            .number.precision(.fractionLength(0...2)).grouping(.never)
                .locale(Locale(identifier: "en_US_POSIX")))
    }

    private static func historyLine(_ past: PastResult) -> String {
        var when = [dateFormatter.string(from: past.recordedAt), past.moisture.rawValue]
        if let stage = past.cropStage { when.append(stage.label.lowercased()) }
        return
            "- \(when.joined(separator: ", ")): "
            + "\(figures(perFrame: past.organismsPerFrame, kinds: past.interpretedKinds)), \(words(past.level))."
    }

    /// "1.5 per frame, 3 kinds", shared by the sample line and the history lines.
    private static func figures(perFrame: Double, kinds: Int) -> String {
        "\(String(format: "%.1f", perFrame)) per frame, \(kinds == 1 ? "1 kind" : "\(kinds) kinds")"
    }

    private static func bandWord(_ band: CountBands.Band) -> String {
        switch band {
        case .low: return "low"
        case .typical: return "typical"
        case .high: return "high"
        }
    }

    private static func words(_ level: SoilHealthEstimate.Level) -> String {
        switch level {
        case .good, .fair, .poor: return level.rawValue
        case .tooFewToSay: return "too few to say"
        case .notCounted: return "not counted"
        }
    }

    /// "12 Oct 2026", the same on every phone. UTC, so tests are stable; a sample taken near
    /// midnight can show the neighbouring day.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}
