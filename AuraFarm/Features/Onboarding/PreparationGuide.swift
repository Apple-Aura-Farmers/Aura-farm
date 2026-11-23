import Foundation

/// What the preparation flow shows, as data: the kit to gather, and the steps for the slide
/// and the microscope.
///
/// The amounts come from `SamplePreparation` rather than being written out here, because a
/// count is only worth as much as the slide it came from: the guide and the report have to
/// say the same thing about how the sample was made.
enum PreparationGuide {
    /// One thing to have on the table before starting.
    struct Material: Identifiable, Equatable {
        /// Stable across a change of wording, because it is what a tick is remembered under.
        var id: String
        var title: String
        var detail: String
    }

    /// One instruction, with the animation that shows it.
    struct Step: Identifiable, Equatable {
        var id: Int
        var title: String
        var detail: String
        /// The animation this step shows; see `OnboardingAnimation`.
        var animation: String
    }

    /// A run of steps shown as one section of the flow.
    struct Section: Identifiable, Equatable {
        var id: String
        var title: String
        /// Under the title. Each step may replace it with its own.
        var subtitle: String
        var steps: [Step]
        /// Whether the steps are paged through with the arrows, or confirmed one at a time.
        var paging: Paging

        enum Paging: Equatable {
            /// Arrows either side of the animation, and Continue at the end.
            case arrows
            /// Done on each step, which moves to the next one.
            case confirmEach
        }
    }

    // MARK: - What you'll need

    private static let phoneMount = Material(
        id: "phone-mount", title: "Phone mount", detail: "To attach phone to microscope")
    private static let microscope = Material(
        id: "microscope", title: "Compound Microscope",
        detail: "Any type of microscope that allows 40x")
    private static let distilledWater = Material(
        id: "distilled-water", title: "Distilled water", detail: "For the soil sample testing")
    private static let pipette = Material(
        id: "pipette", title: "Pipette or dropper",
        detail: "For liquid transfer to the sample slide")
    private static let slides = Material(
        id: "slides", title: "Microscope slides", detail: "Clean glass preferred")
    private static let coverSlides = Material(
        id: "cover-slides", title: "Cover slides", detail: "22mm x 22mm works well")

    /// The kit, which differs by who makes the slide.
    ///
    /// Somebody handed a prepared sample still needs the beaker and water: the jar's job
    /// changes with the flow, so its line does rather than the list dropping it.
    static func materials(preparingSample: Bool) -> [Material] {
        let jar = Material(
            id: "jar", title: "Small jar or beaker",
            detail: preparingSample ? "Hold soil sample for dilution" : "To hold the soil sample")
        let soil = Material(
            id: "soil-sample", title: "Soil Sample", detail: "From the field helpers")
        let rest = [microscope, jar, distilledWater, pipette, slides, coverSlides]
        return preparingSample ? [phoneMount] + rest : [phoneMount, soil] + rest
    }

    // MARK: - Sections

    /// Making the slide. Shown only to whoever prepares the sample themselves.
    static let soilSample = Section(
        id: "soil-sample",
        title: "Soil Sample",
        subtitle: "This should be observed between 1-2 hours for more accurate results",
        steps: [
            Step(
                id: 1, title: "Use clean tools.",
                detail: "Contaminated tools can kill the microorganisms you're looking for.",
                animation: "soil-1-clean-tools"),
            Step(
                id: 2, title: "Avoid large clumps.",
                detail: "Ensure the fresh soil sample stays as consistent as possible.",
                animation: "soil-2-clumps"),
            Step(
                id: 3, title: "Add \(SamplePreparation.gramsOfSoil.formatted())g of fresh soil.",
                detail:
                    "Approximately \(SamplePreparation.gramsOfSoil.formatted())g of fresh soil in "
                    + "the beaker and tap it to level the soil.",
                animation: "soil-3-weigh"),
            Step(
                id: 4,
                title:
                    "Add \(SamplePreparation.millilitresOfWater.formatted())mL of distilled water.",
                detail: "Stir the mixture gently for 30 seconds and let it sit for another 30 "
                    + "seconds.",
                animation: "soil-4-water"),
            Step(
                id: 5, title: "Pipette one drop of supernatant.",
                detail: "Once the sediment settles, pipette 1 drop of the cloudy water "
                    + "(supernatant) onto the slide.",
                animation: "soil-5-pipette"),
            Step(
                id: 6, title: "Lower slip at 45° angle.",
                detail: "Run it back and forth across the area where the coverslip should fall. "
                    + "Then drop it down.",
                animation: "soil-6-cover-slip"),
        ],
        paging: .arrows)

    /// Getting the phone looking down the eyepiece. Every flow ends here.
    static let microscopeSetUp = Section(
        id: "microscope",
        title: "Microscope",
        subtitle: "Ensure the microscope is evenly lit, and your phone is aligned to the eyepiece.",
        steps: [
            Step(
                id: 1, title: "Attach your phone to microscope.",
                detail: "Using the phone mount attach your phone. Then, ensure it is aligned to "
                    + "the eyepiece.",
                animation: "scope-1-mount"),
            Step(
                id: 2, title: "Turn the stage knob.",
                detail: "Turn to focus so that you can see the sample clearly on your phone "
                    + "screen.",
                animation: "scope-2-focus"),
        ],
        paging: .confirmEach)

    /// Every section of the flow in order, the checklist first.
    ///
    /// The count is what the bar at the top divides itself into, so a flow that skips making
    /// the slide shows two segments rather than three.
    static func sections(preparingSample: Bool) -> [Section] {
        preparingSample ? [soilSample, microscopeSetUp] : [microscopeSetUp]
    }
}
