#if DEBUG
    import SwiftUI

    /// A page setup step beside the lab's drawing of the same step (`SetupPreviewPanel`, which uses
    /// the same overlay views the page draws): the indicator and sentence the page adds, over the
    /// lab's own picture.
    private struct PageStepPreview: View {
        var stage: GuidedScanSetupStage
        var scene: SetupPreviewPanel.Scene?

        var body: some View {
            VStack(spacing: 12) {
                HStack {
                    Text(stage.indicator).bold()
                    Spacer()
                }
                .font(.title3)
                if let scene {
                    SetupPreviewPanel(scene: scene)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.4)).frame(height: 220)
                        .overlay(Text("Camera, nothing analysed").font(.caption))
                }
                Text(stage.sentence)
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding()
            .background(.black)
            .foregroundStyle(.white)
        }
    }

    #Preview("Page step 1: align") { PageStepPreview(stage: .align, scene: .alignClippedRight) }
    #Preview("Page step 2: focus") { PageStepPreview(stage: .focus, scene: .focusTurnOneWay) }
    #Preview("Page step 3: check the outline") { PageStepPreview(stage: .field, scene: nil) }
    #Preview("Page step 4: knobs") { PageStepPreview(stage: .stage, scene: .stageWaitX) }
    #Preview("Page: ready") { PageStepPreview(stage: .ready, scene: nil) }
#endif
