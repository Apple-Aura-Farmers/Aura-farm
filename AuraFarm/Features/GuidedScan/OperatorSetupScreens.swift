import SwiftUI

// The microscope operator's setup screens: Start, 1 Alignment, 3 Focus. They sit over the guided
// scan page and read the same engine; nothing here decides a step, it only draws what the lab's
// checks say. Step 2 (the field) keeps the page's own views.

// MARK: What the screens show, from the lab's readings

/// Alignment as the operator sees it: still adjusting, the circle is not in the frame, or good.
enum OperatorAlignState: Equatable {
    case adjusting, outOfView, good

    init(reading: AlignmentReading, passed: Bool) {
        if passed {
            self = .good
        } else if !reading.found || !reading.clippedSides.isEmpty {
            self = .outOfView
        } else {
            self = .adjusting
        }
    }
}

/// The focus gauge: the pill, and where the marker sits (-1 not far enough ... 1 too far).
/// Before the knob has shown a direction the pill says to keep turning and the marker sits by the left end.
struct OperatorFocusGauge: Equatable {
    enum Tone { case searching, needsSample, almost, turnBack, hold }

    var tone: Tone
    var offset: Double

    var label: String {
        switch tone {
        case .searching: "Turn slowly."
        case .needsSample: "Move to an area with sample."
        case .almost: "Almost there."
        case .turnBack: "Turn back slowly."
        case .hold: "Hold Steady."
        }
    }

    var symbol: String {
        switch tone {
        case .searching: "arrow.triangle.2.circlepath"
        case .needsSample: "exclamationmark.circle"
        case .almost: "minus.circle"
        case .turnBack: "x.circle"
        case .hold: "checkmark.circle"
        }
    }

    init(reading: FocusReading?, dial: FocusDialReading?) {
        if reading?.state == .focused || dial?.isGreen == true {
            tone = .hold
            offset = dial.map { min(abs($0.offset), $0.greenHalfWidth) * ($0.offset < 0 ? -1 : 1) } ?? 0
        } else if reading?.state == .passedPeak || dial?.side == .past || dial?.isWrongWay == true {
            tone = .turnBack
            offset = max(dial?.offset ?? 0.9, 0.3)
        } else if reading?.state == .nearPeak || dial != nil {
            tone = .almost
            offset = dial?.offset ?? -(1 - (reading?.level ?? 0.85))
        } else {
            tone = reading?.state == .needsSample ? .needsSample : .searching
            offset = -(1 - (reading?.level ?? 0))
        }
    }
}

// MARK: Pieces

/// Four corners of a square, like a viewfinder.
private struct CornerBrackets: Shape {
    var arm: CGFloat = 96

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
        }
        return path
    }
}

/// The small centre mark: a ring with a plus.
private struct CentreMark: View {
    var body: some View {
        ZStack {
            Circle().stroke(.white, lineWidth: 2)
            Image(systemName: "plus").font(.system(size: 36, weight: .light))
        }
        .frame(width: 56, height: 56)
        .foregroundStyle(.white)
    }
}

/// A status pill: "Almost there.", "Turn back slowly.", "Hold Steady.".
private struct FocusPill: View {
    var gauge: OperatorFocusGauge

    private var colour: Color {
        switch gauge.tone {
        case .searching: .white
        case .needsSample: .orange
        case .almost: .yellow
        case .turnBack: .red
        case .hold: .green
        }
    }

    var body: some View {
        Label(gauge.label, systemImage: gauge.symbol)
            .font(.subheadline)
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(colour.opacity(0.45), in: Capsule())
            .overlay(Capsule().stroke(colour, lineWidth: 1))
    }
}

/// Red at both ends, green in the middle, and a marker under it.
private struct FocusTickBar: View {
    var offset: Double
    private let count = 66

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            VStack(spacing: 4) {
                HStack(spacing: 1.5) {
                    ForEach(0..<count, id: \.self) { index in
                        // 0 at the middle, 1 at either end; green only in the middle third.
                        let distance = abs(Double(index) / Double(count - 1) * 2 - 1)
                        Rectangle().fill(
                            Color(hue: 0.33 * max(0, 1 - distance * 1.5), saturation: 1, brightness: 1))
                    }
                }
                .frame(height: 18)
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white)
                    .offset(x: CGFloat(min(max(offset, -1), 1)) * width / 2)
                    .animation(.easeOut(duration: 0.15), value: offset)
            }
        }
        .frame(height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Focus")
    }
}

/// The knob and a lime arrow turning round it: "turn the focus knob slowly in one direction".
private struct FocusKnobIntro: View {
    @State private var turn = false

    var body: some View {
        HStack(spacing: 12) {
            Image("Knob")
                .resizable().scaledToFit()
                .frame(width: 150)
            ZStack {
                Capsule().fill(Color.auraGreen).frame(width: 8, height: 150)
                Image(systemName: "chevron.up")
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(Color.auraGreen)
                    .offset(y: turn ? -75 : 75)
                    .opacity(turn ? 1 : 0.35)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                turn = true
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Screens

/// The first screen after the stage is chosen: "Sample Analysis".
struct OperatorStartScreen: View {
    var onStart: () -> Void

    var body: some View {
        ZStack {
            Color.black
            // Equal gaps above the title, between the blocks and above the button.
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Sample Analysis").font(.system(size: 30, weight: .bold))
                    Text("Align phone and microscope circle in view, round, evenly lit and no glare.")
                        .font(.callout).multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image("Microscope")
                    .resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 315)
                    .clipped().blur(radius: 2)
                Spacer()
                Button(action: onStart) {
                    Label("Start Aligning", systemImage: "play.fill")
                        .font(.title3.weight(.medium))
                        .padding(.horizontal, 24).padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .tint(.auraGreen).foregroundStyle(.black)
                Spacer()
            }
            .padding(.vertical, 60)
        }
        .foregroundStyle(.white)
    }
}

/// Step 1, first screen: what to do, before the live view. Continue goes to the live screen.
struct OperatorAlignIntro: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black
            // The picture group, the words and the button as one block, centred on the screen.
            VStack(spacing: 36) {
                ZStack {
                    // A picture of the microscope view, not the camera: this screen only says
                    // what to do next.
                    Image("Microscope")
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 315)
                        .clipped().blur(radius: 6).opacity(0.5)
                    CornerBrackets()
                        .stroke(.white, style: StrokeStyle(lineWidth: 4, lineJoin: .round))
                        .frame(width: 373, height: 373)
                    Circle().stroke(.white, lineWidth: 8).frame(width: 272, height: 272)
                        .shadow(color: .white.opacity(0.6), radius: 10)
                    CentreMark()
                }
                .frame(height: 373)
                Text("Now, ensure eyepiece field is within the frame (square bounding box).")
                    .font(.callout).multilineTextAlignment(.center)
                    .frame(maxWidth: 275)
                Button("Continue", action: onContinue)
                    .font(.title3.weight(.medium))
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .controlSize(.large)
                    .tint(.auraGreen).foregroundStyle(.black)
            }
            // Nudged up a little: the close button and home indicator sit unevenly at the edges.
            .offset(y: -20)
        }
        .foregroundStyle(.white)
    }
}

/// Step 1, live: drawn over the page's own camera picture, which fills the screen. Red corners when the circle is not in the frame,
/// green when it is good (the page then moves on by itself).
struct OperatorAlignScreen: View {
    var model: ScanEngine

    private var state: OperatorAlignState {
        .init(reading: model.setupInfo.alignment, passed: model.setupInfo.isAlignmentPassed)
    }

    private var colour: Color {
        switch state {
        case .adjusting: .white
        case .outOfView: Color(red: 1, green: 0.13, blue: 0.13)
        case .good: Color(red: 0.2, green: 0.78, blue: 0.35)
        }
    }

    var body: some View {
        ZStack {
            CornerBrackets()
                .stroke(colour, style: StrokeStyle(lineWidth: state == .good ? 6 : 4, lineJoin: .round))
                .frame(width: 373, height: 373)
            CentreMark()
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.2), value: state)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            state == .good ? "Aligned" : state == .outOfView ? "Eyepiece out of view" : "Aligning")
    }
}

/// Step 3: the focus knob. The knob until a direction shows, then the gauge.
struct OperatorFocusScreen: View {
    var model: ScanEngine
    /// The knob shows for a moment, then the gauge stays so the operator can tune to sharp.
    @State private var showsKnob = true

    private var gauge: OperatorFocusGauge {
        .init(reading: model.focusMeter.reading, dial: model.focusMeter.dial)
    }

    var body: some View {
        // Over the page's own picture: the round view, dark outside it.
        ZStack {
            // Already sharp: no knob to turn.
            if showsKnob, gauge.tone != .hold {
                Circle().fill(.black.opacity(0.55)).frame(width: 292, height: 292)
                FocusKnobIntro()
                Text("Turn the focus knob slowly in one direction")
                    .font(.callout).multilineTextAlignment(.center)
                    .frame(maxWidth: 230)
                    .offset(y: 150)
            } else {
                FocusPill(gauge: gauge).offset(y: -300)
                FocusTickBar(offset: gauge.offset)
                    .padding(.horizontal, 36).offset(y: 235)
            }
        }
        .foregroundStyle(.white)
        .animation(.easeOut(duration: 0.2), value: showsKnob)
        .animation(.easeOut(duration: 0.2), value: gauge)
        .task {
            try? await Task.sleep(for: .seconds(2))
            showsKnob = false
        }
    }
}

#Preview("Gauge pills") {
    VStack(spacing: 16) {
        FocusPill(
            gauge: .init(
                reading: nil,
                dial: .init(
                    offset: -0.4, side: .approaching, greenHalfWidth: 0.1, isGreen: false, isWrongWay: false,
                    message: "")))
        FocusPill(
            gauge: .init(reading: .init(state: .passedPeak, current: 1, peak: 1, level: 0.8), dial: nil))
        FocusPill(gauge: .init(reading: .init(state: .focused, current: 1, peak: 1, level: 1), dial: nil))
        FocusTickBar(offset: -0.4).padding(.horizontal, 36)
        FocusKnobIntro()
    }
    .padding().background(.black).foregroundStyle(.white)
}

// MARK: Scan (detection)

enum OperatorScanPhase: Equatable { case moving, slowDown, complete }

/// The green ring round the round view, and its badge: the arrow (manual stage only), the hand
/// for "slow down", the check when done. Drawn over the page's camera picture.
struct OperatorScanRing: View {
    /// The learned round view in the picture; nil falls back to a centred circle.
    var circle: CGRect?
    var phase: OperatorScanPhase
    var showsArrow: Bool
    /// Finished share of all columns, 0 to 1; the ring is full for slow down and done.
    var fraction: Double
    /// Where the guide says to move, in screen axes; nil keeps the arrow pointing up.
    var direction: CGPoint?

    private var badge: String? {
        switch phase {
        case .complete: "Check"
        case .slowDown: "Hand"
        case .moving: showsArrow ? "Arrow" : nil
        }
    }

    private var turn: Angle {
        guard let d = direction, d != .zero else { return .zero }
        return .radians(atan2(d.y, d.x) + .pi / 2)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = circle.map { $0.width + 6 } ?? min(proxy.size.width, proxy.size.height) * 0.83
            let middle =
                circle.map { CGPoint(x: $0.midX, y: $0.midY) }
                ?? CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 12)
                Circle().trim(from: 0, to: phase == .moving ? max(fraction, 0.03) : 1)
                    .stroke(Color.auraGreen, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if let badge {
                    // The assets are the circle with the icon in it: drawn as they are.
                    Image(badge).resizable().scaledToFit().frame(width: 110, height: 110)
                        // The arrow asset points up; turn it to where the guide goes.
                        .rotationEffect(badge == "Arrow" ? turn : .zero)
                        .animation(.easeOut(duration: 0.25), value: turn)
                }
            }
            .frame(width: side, height: side)
            .position(middle)
        }
        .animation(.easeOut(duration: 0.2), value: phase)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One block per column, grey until the column is finished, then green.
struct OperatorColumnBlocks: View {
    var done: Int
    var total: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(18), spacing: 4), count: 4), spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(index < done ? Color.auraGreen : .white.opacity(0.25))
                    .frame(height: 18)
            }
        }
        .frame(width: 18 * 4 + 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(total) columns done")
    }
}

/// Over the finished scan until the results open: dims it and shows the logo mark in a spinning ring.
struct OperatorLoadingScreen: View {
    @State private var spins = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.75)
            VStack(spacing: 10) {
                ZStack {
                    Circle().trim(from: 0, to: 0.75)
                        .stroke(Color.auraGreen, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 104, height: 104)
                        .rotationEffect(.degrees(spins ? 360 : 0))
                    // The mark only: the top of the logo, without its name.
                    Image("Icon").resizable().scaledToFit().frame(width: 56)
                        .frame(height: 56 * 450 / 524, alignment: .top).clipped()
                }
                Text("Loading..").font(.callout).foregroundStyle(Color.auraGreen)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) { spins = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading results")
    }
}
