import SwiftUI

/// The form for what a clip is of. Shown on its own before the camera opens, and again
/// from the options menu when the sample changes.
struct SampleDetailsView: View {
    @Binding var details: RecordingMetadata

    var body: some View {
        Form {
            Section("Sample") {
                TextField("Sample ID", text: $details.sampleID)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Stepper("Field \(details.field)", value: $details.field, in: 1...999)
                Picker("Soil", selection: $details.moisture) {
                    ForEach(RecordingMetadata.Moisture.allCases) { moisture in
                        Text(moisture.label).tag(moisture)
                    }
                }
            }
            Section("Amounts") {
                NumberRow(title: "Grams of soil", value: $details.gramsOfSoil)
                NumberRow(title: "mL scanned", value: $details.millilitresScanned)
            }
        }
    }
}

/// Starts empty rather than at 0, so an untyped amount never looks like a measured one.
private struct NumberRow: View {
    let title: String
    @Binding var value: Double?
    @State private var text = ""

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 110)
                .accessibilityLabel(title)
                .onChange(of: text) { _, typed in
                    // Accepts a decimal comma, which some keyboards give instead of a point.
                    value = Double(typed.replacingOccurrences(of: ",", with: "."))
                }
        }
        .onAppear { text = value.map { $0.formatted(.number) } ?? "" }
    }
}

#Preview {
    SampleDetailsView(
        details: .constant(
            RecordingMetadata(
                sampleID: "A12",
                field: 1,
                moisture: .drained,
                gramsOfSoil: 10,
                millilitresScanned: 0.5,
                recordedAt: .now
            )
        ))
}
