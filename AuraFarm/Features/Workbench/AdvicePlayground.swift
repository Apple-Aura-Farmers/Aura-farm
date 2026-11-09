#if DEBUG
    import Playgrounds

    // Change the case id or the prompt text here to try ideas quickly in Xcode, then move what
    // works into the app's code. Run it from the gutter next to the #Playground line, on a Mac
    // or phone with Apple Intelligence.
    #Playground("Advice for one sample") {
        guard let evalCase = AdviceEvalCases.all.first(where: { $0.id == "euglenoids-fertilized" }) else {
            print("No such case")
            return
        }
        let estimate = PlaceholderSoilHealthEstimator().estimate(evalCase.result)
        let context = AdviceContextBuilder().context(
            for: evalCase.result, estimate: estimate, history: evalCase.history)

        print(AdvicePromptBuilder.instructions())
        print(AdvicePromptBuilder.prompt(for: context))

        let clock = ContinuousClock()
        let start = clock.now
        let (advice, outcome) = try await FoundationModelRecommender().generate(
            for: context, freshWording: false, onProgress: { _ in })
        let elapsed = clock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18

        print(advice)
        print(outcome.findings)
        print(
            AdviceAutoGrade.grade(advice: advice, outcome: outcome, context: context, seconds: seconds))
    }
#endif
