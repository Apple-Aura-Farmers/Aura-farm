import SwiftUI

/// A form row with its name on the left and the box on the right, so a field keeps its name
/// once something is typed in it. A plain text field in an iPhone form shows only its prompt.
struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    var prompt = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        LabeledContent(label) {
            TextField(label, text: $text, prompt: Text(prompt))
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
        }
    }
}
