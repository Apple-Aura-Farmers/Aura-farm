import Foundation

extension String {
    /// This text in the phone's language when the string catalog has it, and unchanged when it
    /// does not.
    ///
    /// For the advice content, which stays in English where it is written: the same words are
    /// handed to the on-device model, hashed into `AdviceContentVersion` and kept with saved
    /// advice, so translating them at the source would change all three with the phone's
    /// language. They are translated only here, where they are shown. Words the model wrote
    /// itself have no entry in the catalog and come back as they are.
    var translated: String {
        Bundle.main.localizedString(forKey: self, value: self, table: nil)
    }
}
