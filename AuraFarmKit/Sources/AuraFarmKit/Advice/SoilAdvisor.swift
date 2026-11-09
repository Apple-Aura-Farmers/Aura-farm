import Foundation

/// Works out what to do about a field from its latest NPK results and its microscope counts.
///
/// The fertilizer plan comes from the NPK results alone. The microscope counts are raw and not
/// calibrated, so they never change a dose: they only ask for a slide to be checked or a test to
/// be repeated.
public enum SoilAdvisor {
    /// NPK results older than this are from before the last crop, so the plan built on them is
    /// trusted less. About one rice season. Not calibrated.
    public static let staleAfterDays = 120

    /// A count below this share of the previous comparable count is called out. Not calibrated:
    /// a starting point until counts are checked against expert counts.
    public static let dropShareToMention = 0.5

    /// Counts smaller than this are too few to compare. Not calibrated.
    public static let minimumCountToCompare = 10

    /// - Parameters:
    ///   - nutrients: The field's latest NPK results, if any.
    ///   - organisms: The field's microscope soil tests, in any order.
    ///   - areaHectares: The field's planted area, to give doses for the whole field.
    ///   - now: Today, to judge how old the NPK results are.
    /// - Returns: nil when there is nothing to go on.
    public static func advise(
        nutrients: NutrientResult?,
        organisms: [OrganismCountSummary],
        areaHectares: Double? = nil,
        now: Date = Date()
    ) -> SoilAdvice? {
        guard nutrients != nil || !organisms.isEmpty else { return nil }

        var actions: [AdviceAction] = []
        var retests: [String] = []
        var basis: [String] = []
        var doses: [FertilizerDose] = []
        let confidence: AdviceConfidence

        if let nutrients {
            doses = Self.doses(for: nutrients, areaHectares: areaHectares)
            actions += Self.acidityActions(for: nutrients.pH)
            actions += Self.missingNutrientActions(for: nutrients)
            confidence = Self.confidence(for: nutrients, now: now)
            retests.append("Test the NPK again before the next planting.")
            if let pH = nutrients.pH, SoilAcidity(pH: pH).needsLabTest {
                retests.append(
                    "Send a soil sample to a lab before changing the pH. How much to add depends on it."
                )
            }
            if nutrients.source == .soilTestKit {
                retests.append("If the crop does poorly on this plan, send a soil sample to a lab.")
            }
            basis.append(PaddyFertilizerGuide.basis)
            if nutrients.straw == .unknown, nutrients.levels[.potassium].map({ $0 < .high }) == true {
                basis.append("Straw not recorded, so the KCl dose assumes it was taken away.")
            }
        } else {
            actions.append(
                AdviceAction(
                    kind: .testing,
                    title: "Test the soil for N, P and K",
                    detail: "Use the paddy soil test kit or a lab. The fertilizer plan needs those results."
                )
            )
            confidence = AdviceConfidence(level: .low, reasons: ["No NPK results for this field yet."])
        }

        actions += Self.organismActions(for: organisms)
        if !organisms.isEmpty {
            basis.append("Microscope counts are raw. They are followed over time but do not change any dose.")
        }

        return SoilAdvice(
            doses: doses,
            actions: actions,
            confidence: confidence,
            retests: retests,
            basis: basis
        )
    }

    // MARK: - Fertilizer

    static func doses(for nutrients: NutrientResult, areaHectares: Double?) -> [FertilizerDose] {
        Nutrient.allCases.compactMap { nutrient -> FertilizerDose? in
            guard let level = nutrients.levels[nutrient] else { return nil }
            let fertilizer = Fertilizer.forNutrient(nutrient)
            let perHectare = PaddyFertilizerGuide.kilogramsPerHectare(
                of: fertilizer,
                level: level,
                straw: nutrients.straw
            )
            let forField = areaHectares.flatMap { $0 > 0 ? perHectare * $0 : nil }
            return FertilizerDose(
                fertilizer: fertilizer,
                level: level,
                kilogramsPerHectare: perHectare,
                kilogramsForField: forField,
                schedule: PaddyFertilizerGuide.schedule(for: fertilizer)
            )
        }
    }

    static func missingNutrientActions(for nutrients: NutrientResult) -> [AdviceAction] {
        let missing = Nutrient.allCases.filter { nutrients.levels[$0] == nil }
        guard !missing.isEmpty else { return [] }
        let names = missing.map(\.name).joined(separator: " and ")
        return [
            AdviceAction(
                kind: .testing,
                title: "Test \(names.lowercased()) too",
                detail: "There is no dose for \(names.lowercased()) until it is tested."
            )
        ]
    }

    // MARK: - pH

    /// Actions for the soil's pH. The slightly acidic advice is the PUTS guidance as applied by
    /// BSIP Papua; the rest only sends the helper to the extension officer and a lab, since the
    /// amounts depend on measurements this app does not have.
    static func acidityActions(for pH: Double?) -> [AdviceAction] {
        guard let pH else { return [] }
        switch SoilAcidity(pH: pH) {
        case .veryAcidic, .acidic:
            return [
                AdviceAction(
                    kind: .soil,
                    title: "Ask the extension officer about liming",
                    detail: "The soil is acidic (pH \(Self.oneDecimal(pH))). Agricultural lime or dolomite "
                        + "can raise it, but the amount needs a lab test."
                )
            ]
        case .slightlyAcidic:
            return [
                AdviceAction(
                    kind: .soil,
                    title: "Keep the usual drainage and use urea for nitrogen",
                    detail: "The soil is slightly acidic (pH \(Self.oneDecimal(pH))). Nothing else to "
                        + "change for it."
                )
            ]
        case .neutral:
            return []
        case .alkaline:
            return [
                AdviceAction(
                    kind: .soil,
                    title: "Ask the extension officer which nitrogen fertilizer to use",
                    detail: "The soil is alkaline (pH \(Self.oneDecimal(pH))). Have a lab check it "
                        + "before changing the plan."
                )
            ]
        }
    }

    // MARK: - Confidence

    static func confidence(for nutrients: NutrientResult, now: Date) -> AdviceConfidence {
        var level: AdviceConfidence.Level
        var reasons: [String] = []
        switch nutrients.source {
        case .laboratory:
            level = .good
            reasons.append("NPK measured by a soil lab.")
        case .soilTestKit:
            level = .fair
            reasons.append("A field kit reads a class from a colour chart, not an exact amount.")
        }
        let days = Self.daysBetween(nutrients.testedAt, and: now)
        if days > staleAfterDays {
            level = level.lowered
            reasons.append("Tested \(days) days ago. The soil has likely changed since the last crop.")
        }
        if nutrients.levels.count < Nutrient.allCases.count {
            level = level.lowered
            reasons.append("Not every nutrient was tested.")
        }
        reasons.append("These doses have not been checked on this farm.")
        return AdviceConfidence(level: level, reasons: reasons)
    }

    // MARK: - Organisms

    static func organismActions(for organisms: [OrganismCountSummary]) -> [AdviceAction] {
        let newestFirst = organisms.sorted { $0.recordedAt > $1.recordedAt }
        guard let latest = newestFirst.first else { return [] }

        if latest.total == 0 {
            return [
                AdviceAction(
                    kind: .organisms,
                    title: "Check the slide and test again",
                    detail: "No organisms were counted on the last slide. That usually means a sampling "
                        + "problem, not empty soil: check the preparation."
                )
            ]
        }

        let previous = newestFirst.dropFirst().first { $0.preparationKey == latest.preparationKey }
        if let previous,
            previous.total >= minimumCountToCompare,
            Double(latest.total) < Double(previous.total) * dropShareToMention
        {
            return [
                AdviceAction(
                    kind: .organisms,
                    title: "Repeat the microscope test",
                    detail: "Fewer organisms were counted than last time (\(latest.total), was "
                        + "\(previous.total)). Test again with the same preparation before reading "
                        + "anything into it."
                )
            ]
        }
        return []
    }

    // MARK: - Helpers

    /// Whole days from one date to another, never negative.
    static func daysBetween(_ start: Date, and end: Date) -> Int {
        max(0, Int(end.timeIntervalSince(start) / 86_400))
    }

    /// "5.4", the way a pH is read out. Plain arithmetic so it reads the same on every system.
    static func oneDecimal(_ value: Double) -> String {
        let tenths = Int((value * 10).rounded())
        let sign = tenths < 0 ? "-" : ""
        return "\(sign)\(abs(tenths) / 10).\(abs(tenths) % 10)"
    }
}
