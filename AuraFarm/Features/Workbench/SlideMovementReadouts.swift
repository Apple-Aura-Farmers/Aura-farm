#if DEBUG
    import SwiftUI

    /// Seconds of stillness the stops test asks for.
    let slideLabStillGoalSeconds = 2.0

    /// The big numbers under the camera strip: distance, stillness, hops.
    struct BigReadouts: View {
        var model: SlideMovementLabModel

        /// The line under "Off start": hidden with no start picture.
        private func pictureCheckLine(_ readouts: SlideMovementInfo.Readouts) -> String? {
            switch readouts.pictureCheck {
            case "out_of_range": return "Picture check: come back within 0.4 field of the start"
            case "matching": return "Picture check: matching…"
            case "confirmed":
                guard let truth = readouts.trueOffStartFields,
                    let error = readouts.trackerErrorFields
                else { return nil }
                // The tracker's own distance from the start is the "Off start" number.
                return String(
                    format: "Picture check: true %.2f · tracker %.2f · error %.2f field", truth,
                    readouts.offStartFields ?? truth, error)
            default: return nil
            }
        }

        var body: some View {
            let readouts = model.readouts
            VStack(spacing: 0) {
                HStack {
                    // From the marked start if there is one, otherwise from the last reset.
                    Text(
                        "\(readouts.offStartFields == nil ? "Moved" : "Off start") \(readouts.distanceFields, specifier: "%.2f") fields"
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
                if let line = pictureCheckLine(readouts) {
                    Text(line)
                        .font(.footnote.monospaced())
                        .padding(.horizontal)
                }
            }
        }
    }

    /// The guide dry run: what the guide would say, in plain type. The Phase 3 guide will draw
    /// the crosshairs; this only reads out.
    struct GuideReadout: View {
        var model: SlideMovementLabModel

        var body: some View {
            let info = model.guideInfo
            VStack(alignment: .leading, spacing: 4) {
                Text(info.instruction.isEmpty ? "Guide: waiting…" : info.instruction)
                    .font(.title2.bold())
                Text("Route: \(info.state.isEmpty ? "-" : info.state)")
                if let dx = info.targetDx, let dy = info.targetDy {
                    Text("Target: dx \(dx, specifier: "%.2f"), dy \(dy, specifier: "%.2f") fields")
                } else {
                    Text("Target: -")
                }
                Text("View: \(info.viewClass.isEmpty ? "-" : info.viewClass) · Captured: \(info.captures)")
            }
            .font(.footnote.monospaced())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
            .padding(.bottom, 4)
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
                if let box = readouts.boxStats {
                    Text(
                        "box sharp \(box.sharpness, specifier: "%.0f") · contrast \(box.contrast, specifier: "%.0f") · bright \(box.brightness, specifier: "%.0f")"
                    )
                } else {
                    Text("No frames yet")
                }
                if let stats = readouts.stats {
                    Text(
                        "whole frame: sharp \(stats.sharpness, specifier: "%.0f") · contrast \(stats.contrast, specifier: "%.0f") · bright \(stats.brightness, specifier: "%.0f")"
                    )
                    .foregroundStyle(.secondary)
                }
                Text(
                    "Reading: \(readouts.reading.isEmpty ? "-" : readouts.reading)\(readouts.hasDetail ? "" : " · NO DETAIL") · blind stretches \(readouts.blindStretches)"
                )
                Text(
                    "pos \(readouts.position.x, specifier: "%.0f"), \(readouts.position.y, specifier: "%.0f") px  =  \(readouts.positionFields.x, specifier: "%.2f"), \(readouts.positionFields.y, specifier: "%.2f") fields"
                )
                Text(
                    "Box \(readouts.boxSide, specifier: "%.0f") px · hop at \(readouts.hopLimit, specifier: "%.0f") px"
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
                Text("Label statistics (inside the box)").font(.subheadline.bold())
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
                    if let stats = model.readouts.boxStats {
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
                .sensoryFeedback(.impact(weight: .light), trigger: model.guideInfo.captureCount)
                .sensoryFeedback(.impact(weight: .light), trigger: model.guideInfo.edgeCount)
                .sensoryFeedback(.success, trigger: stopReached) { _, reached in reached }
        }
    }
#endif
