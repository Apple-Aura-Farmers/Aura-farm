import AuraFarmKit
import SwiftData
import SwiftUI

/// Starts a growing season on a field, or edits one: the variety, when it was transplanted and
/// harvested, and the yield.
struct SeasonEditorView: View {
    let field: Field
    /// nil to start a new season.
    let season: Season?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var variety = ""
    @State private var isPlanted = true
    @State private var plantedOn = Date.now
    @State private var isHarvested = false
    @State private var harvestedOn = Date.now
    /// Typed as text so an empty box means "not entered" rather than zero.
    @State private var yieldText = ""
    @State private var totalHarvestText = ""
    @State private var notes = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(season == nil ? "New Season on \(field.name)" : "Edit Season")
                .font(.headline)
                .padding([.top, .horizontal], 20)

            Form {
                Section {
                    TextField("Season", text: $name, prompt: Text("For example, Wet season 2026–27"))
                    TextField("Rice variety", text: $variety, prompt: Text("Optional, for example Inpari 32"))
                }

                Section {
                    Toggle("Transplanted", isOn: $isPlanted)
                    if isPlanted {
                        DatePicker("Transplanted on", selection: $plantedOn, displayedComponents: .date)
                    }
                } footer: {
                    Text("The fertilizer plan shows dates counted from the transplanting date.")
                }

                Section {
                    Toggle("Harvested", isOn: $isHarvested)
                    if isHarvested {
                        DatePicker("Harvested on", selection: $harvestedOn, displayedComponents: .date)
                        TextField(
                            "Yield (t/ha)",
                            text: $yieldText,
                            prompt: Text("Unhusked rice, for example 5.8")
                        )
                        TextField(
                            "Or total harvest (kg)",
                            text: totalHarvestBinding,
                            prompt: Text(totalHarvestPrompt)
                        )
                        .disabled(field.areaHectares == nil)
                    }
                } header: {
                    Text("Harvest")
                } footer: {
                    if isHarvested && !yieldText.isBlank && yield == nil {
                        Text("Enter the yield as a number of tonnes a hectare, up to 20.")
                            .foregroundStyle(.red)
                    } else if isHarvested {
                        Text("A total harvest is turned into tonnes a hectare using the field's area.")
                    }
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 420, idealHeight: 520)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(season == nil ? "Start Season" : "Save") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding([.bottom, .horizontal], 20)
        }
        .frame(width: 460)
        .onAppear(perform: load)
    }

    private var totalHarvestPrompt: String {
        field.areaHectares == nil ? "Enter the field's area first" : "Optional"
    }

    /// Typing a total harvest fills in the yield from it.
    private var totalHarvestBinding: Binding<String> {
        Binding(
            get: { totalHarvestText },
            set: { text in
                totalHarvestText = text
                if let total = Self.number(from: text),
                    let perHectare = HarvestYield.tonnesPerHectare(
                        totalKilograms: total,
                        areaHectares: field.areaHectares
                    )
                {
                    yieldText = ((perHectare * 100).rounded() / 100).formatted(.number)
                }
            }
        )
    }

    /// Tonnes a hectare, when entered and plausible for rice. 20 t/ha is well above any record.
    private var yield: Double? {
        guard let number = Self.number(from: yieldText), (0...20).contains(number) else { return nil }
        return number
    }

    private var canSave: Bool {
        !name.isBlank && (!isHarvested || yieldText.isBlank || yield != nil)
    }

    /// Accepts a decimal comma as well as a point.
    private static func number(from text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private func load() {
        guard let season else {
            name = Self.suggestedName(for: .now)
            return
        }
        name = season.name
        variety = season.variety
        isPlanted = season.plantedOn != nil
        plantedOn = season.plantedOn ?? .now
        isHarvested = season.harvestedOn != nil
        harvestedOn = season.harvestedOn ?? .now
        yieldText = season.yieldTonnesPerHectare.map { $0.formatted(.number) } ?? ""
        notes = season.notes
    }

    private func save() {
        let saved: Season
        if let season {
            saved = season
        } else {
            saved = Season(name: name.trimmed)
            modelContext.insert(saved)
            saved.field = field
        }
        saved.name = name.trimmed
        saved.variety = variety.trimmed
        saved.plantedOn = isPlanted ? plantedOn : nil
        saved.harvestedOn = isHarvested ? harvestedOn : nil
        saved.yieldTonnesPerHectare = isHarvested ? yield : nil
        saved.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        dismiss()
    }

    /// "Wet season 2026–27" from November to April, "Dry season 2027" from May to October: the
    /// usual split in Bali. Only a starting point; the helper can type anything.
    static func suggestedName(for date: Date, calendar: Calendar = .current) -> String {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        switch month {
        case 11, 12: return "Wet season \(year)–\(String(year + 1).suffix(2))"
        case 1...4: return "Wet season \(year - 1)–\(String(year).suffix(2))"
        default: return "Dry season \(year)"
        }
    }
}

extension String {
    fileprivate var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    fileprivate var trimmed: String {
        trimmingCharacters(in: .whitespaces)
    }
}
