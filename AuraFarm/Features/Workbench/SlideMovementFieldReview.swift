#if DEBUG
    import SwiftUI

    /// Shown over the preview once the eyepiece field is learned: "Does this look right?" with
    /// Looks right / Adjust. Adjust draws a circle over the preview that can be dragged and
    /// resized; Done hands it back as the field. Tracking waits until the person confirms.
    struct FieldReview: View {
        var info: SlideMovementInfo.Field
        var converter: FramePreviewConverter?
        var onConfirm: () -> Void
        var onAdjust: (FieldCircle) -> Void

        @State private var circle: FieldCircle?
        @State private var dragStart: FieldCircle?

        var body: some View {
            ZStack {
                if let circle, let converter {
                    adjuster(circle: circle, converter: converter)
                }
                VStack {
                    Spacer()
                    controls
                }
                .padding(8)
            }
        }

        private var controls: some View {
            VStack(spacing: 8) {
                if let circle {
                    Text("Drag the circle onto the lens, then set its size.").font(.caption)
                    Slider(value: radius(of: circle), in: radiusRange)
                    HStack {
                        Button("Cancel") { self.circle = nil }
                        Button("Done") {
                            onAdjust(circle)
                            self.circle = nil
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    Text("Does this look right?").font(.headline)
                    Text("Red is the eyepiece. Yellow is where movement is measured.")
                        .font(.caption)
                    HStack {
                        Button("Adjust") { circle = info.circle ?? defaultCircle }
                        Button("Looks right", action: onConfirm)
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .buttonStyle(.bordered)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        }

        private var shortSide: Double { Double(min(info.frameSize.width, info.frameSize.height)) }

        private var radiusRange: ClosedRange<Double> {
            shortSide * FieldCircle.radiusShareRange.lowerBound...shortSide
                * FieldCircle.radiusShareRange.upperBound
        }

        private var defaultCircle: FieldCircle {
            FieldCircle(
                centre: CGPoint(x: info.frameSize.width / 2, y: info.frameSize.height / 2),
                radius: shortSide * 0.4)
        }

        private func radius(of circle: FieldCircle) -> Binding<Double> {
            Binding(
                get: { circle.radius },
                set: { self.circle?.radius = $0 })
        }

        /// The circle drawn on the preview, with a drag that moves it. Frame pixels become preview
        /// points, and back, through the preview layer.
        private func adjuster(circle: FieldCircle, converter: FramePreviewConverter)
            -> some View
        {
            let centre = converter.viewPoint(of: circle.centre)
            let radius = converter.viewRadius(of: circle)
            return Circle()
                .stroke(.white, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                .frame(width: radius * 2, height: radius * 2)
                .position(centre)
                .allowsHitTesting(false)
                .overlay {
                    Color.clear
                        .contentShape(Rectangle())
                        .highPriorityGesture(
                            DragGesture()
                                .onChanged { drag in
                                    let start = dragStart ?? circle
                                    dragStart = start
                                    let from = converter.viewPoint(of: start.centre)
                                    self.circle?.centre = converter.framePoint(
                                        fromView: CGPoint(
                                            x: from.x + drag.translation.width,
                                            y: from.y + drag.translation.height))
                                }
                                .onEnded { _ in dragStart = nil })
                }
        }
    }
#endif
