#if DEBUG
    import SwiftUI

    /// Seconds of stillness the stops test asks for.
    let slideLabStillGoalSeconds = 2.0

    /// The big numbers under the camera strip: distance, stillness, hops.
    struct BigReadouts: View {
        var model: SlideMovementLabModel

        var body: some View {
            let readouts = model.readouts
            HStack {
                // From the marked start if there is one, otherwise from the last reset.
                Text(
                    "\(readouts.offStartFrames == nil ? "Moved" : "Off start") \(readouts.distanceFrames, specifier: "%.2f") fr"
                )
                .foregroundStyle(readouts.isHome ? .green : .primary)
                Text("Still \(readouts.stillSeconds, specifier: "%.1f") s")
                    .foregroundStyle(
                        readouts.stillSeconds >= slideLabStillGoalSeconds ? .green : .primary)
                Text("Hops \(readouts.hops) · Gaps \(readouts.gaps)")
            }
            .font(.title3.monospacedDigit().bold())
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
    }

    /// The small monospaced readout: statistics, position, last event, analysis cost.
    struct TextReadout: View {
        var model: SlideMovementLabModel
        var thresholds = AnalysisLoadThresholds()

        private var fieldText: String {
            switch model.fieldInfo.state {
            case .learning(let progress): "Field: learning \(Int(progress * 100))%"
            case .ready(let mask): "Field: learned (open \(Int((mask.openShare * 100).rounded()))%)"
            case .untrusted: "Field: not found, using centre"
            case nil: "Field: \(model.fieldRegion.title.lowercased())"
            }
        }

        var body: some View {
            let readouts = model.readouts
            let behind = thresholds.isFallingBehind(
                milliseconds: readouts.analysisMilliseconds,
                framesPerSecond: readouts.analyzedFps)
            VStack(alignment: .leading, spacing: 2) {
                if let stats = readouts.stats {
                    Text(
                        "bright \(stats.brightness, specifier: "%.1f")  sharp \(stats.sharpness, specifier: "%.2f")  contrast \(stats.contrast, specifier: "%.1f")"
                    )
                } else {
                    Text("No frames yet")
                }
                Text(
                    "pos \(readouts.position.x, specifier: "%.0f"), \(readouts.position.y, specifier: "%.0f") px  =  \(readouts.positionFrames.x, specifier: "%.2f"), \(readouts.positionFrames.y, specifier: "%.2f") frames"
                )
                Text(fieldText)
                Text("last event: \(readouts.lastEvent.isEmpty ? "-" : readouts.lastEvent)")
                Text(
                    "analysis \(readouts.analysisMilliseconds, specifier: "%.0f") ms · \(readouts.analyzedFps, specifier: "%.1f") fps"
                )
                .foregroundStyle(behind ? .red : .primary)
                .bold(behind)
            }
            .font(.footnote.monospaced())
        }
    }

    /// Contrast and sharpness per label, to see whether they separate.
    struct StatisticsTable: View {
        var model: SlideMovementLabModel

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text("Label statistics").font(.subheadline.bold())
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                    GridRow {
                        Text("")
                        Text("n")
                        Text("contrast 10–50–90")
                        Text("sharpness 10–50–90")
                    }
                    .font(.caption2.bold())
                    ForEach(model.labelSummaries, id: \.label) { summary in
                        GridRow {
                            Text(summary.label)
                                .foregroundStyle(slideLabLabelColor(summary.label))
                                .bold()
                            Text("\(summary.count)")
                            Text(range(summary.contrast))
                            Text(range(summary.sharpness))
                        }
                    }
                    if let stats = model.readouts.stats {
                        GridRow {
                            Text("now").bold()
                            Text("")
                            Text(String(format: "%.1f", stats.contrast))
                            Text(String(format: "%.2f", stats.sharpness))
                        }
                    }
                }
                .font(.caption.monospacedDigit())
                Text("If the ranges overlap, the app can't tell them apart yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }

        private func range(_ spread: LabelStatistics.Spread) -> String {
            String(format: "%.1f–%.1f–%.1f", spread.p10, spread.median, spread.p90)
        }
    }

    /// An invisible view that plays the haptics, so reading the counters redraws nothing else:
    /// a light tap on each hop, a warning on lost, and success when the stops test first holds
    /// still for the goal.
    struct SlideLabHaptics: View {
        var model: SlideMovementLabModel

        var body: some View {
            let stopReached =
                model.test == .stops && model.readouts.stillSeconds >= slideLabStillGoalSeconds
            Color.clear
                .frame(width: 0, height: 0)
                .sensoryFeedback(.impact(weight: .light), trigger: model.readouts.hopCount)
                .sensoryFeedback(.warning, trigger: model.readouts.lostCount)
                .sensoryFeedback(.success, trigger: stopReached) { _, reached in reached }
        }
    }
#endif
