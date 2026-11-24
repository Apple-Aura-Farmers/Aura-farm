import SwiftUI

/// Everything between deciding to run a test and looking down the eyepiece: the kit, then
/// the slide, then the microscope.
///
/// `preparingSample` is what the flow turns on. Somebody handed a ready slide by a field
/// helper skips making one, so the bar at the top shows two segments rather than three and
/// their kit list names the sample as something to have rather than something to mix.
struct PreparationFlow: View {
    var preparingSample: Bool
    /// Called once the last section is done. The scan starts from here.
    var onFinish: () -> Void

    @State private var page = 0

    private var sections: [PreparationGuide.Section] {
        PreparationGuide.sections(preparingSample: preparingSample)
    }

    /// The checklist plus one segment per section.
    private var segments: Int {
        sections.count + 1
    }

    var body: some View {
        VStack(spacing: 16) {
            PreparationProgress(sections: segments, current: page)
                .padding(.top, 8)

            if page == 0 {
                PreparationChecklistPage(
                    materials: PreparationGuide.materials(preparingSample: preparingSample)
                ) {
                    advance()
                }
            } else if let section = sections[safe: page - 1] {
                PreparationStepsPage(section: section) { advance() }
                    // Keyed on the section, so its steps start from the first one rather than
                    // carrying the last section's position over.
                    .id(section.id)
            }
        }
        .auraBackground()
    }

    private func advance() {
        if page >= sections.count {
            onFinish()
        } else {
            withAnimation(.snappy(duration: 0.25)) { page += 1 }
        }
    }
}

extension Array {
    /// The element at `index`, or nil when there is none there.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Makes the slide") {
    PreparationFlow(preparingSample: true) {}
}

#Preview("Handed the sample") {
    PreparationFlow(preparingSample: false) {}
}
