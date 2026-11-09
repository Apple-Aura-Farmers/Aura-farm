import FoundationModels

/// One action the model picks, by id, with a short reason. The app shows the approved
/// wording for the id, never the model's own.
@Generable
struct GeneratedAction {
    @Guide(
        description: "The action's id, exactly as written in 'Actions you may suggest'.",
        .anyOf(AdviceAction.ID.allCases.map(\.rawValue)))
    var id: String

    @Guide(description: "One short sentence on why this fits this sample, at most about 15 words.")
    var why: String
}
