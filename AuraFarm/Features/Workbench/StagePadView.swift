#if DEBUG
    import SwiftUI

    /// Square picture of the stage: X 0...180 left to right, Y 0...180 bottom to top (before flips).
    struct StagePadView: View {
        let current: StagePoint
        var target: StagePoint?
        var path: [StagePoint] = []
        let flipX: Bool
        let flipY: Bool
        /// Called with the snapped point under the finger; `ended` is true on release.
        let onTouch: (StagePoint, _ ended: Bool) -> Void

        var body: some View {
            GeometryReader { geo in
                let size = geo.size.width
                ZStack {
                    Rectangle().fill(Color(.secondarySystemBackground))
                    grid(size)
                    if !path.isEmpty {
                        Path { p in
                            for (i, pt) in path.enumerated() {
                                i == 0 ? p.move(to: place(pt, size)) : p.addLine(to: place(pt, size))
                            }
                        }
                        .stroke(Color.orange, lineWidth: 2)
                        ForEach(Array(path.enumerated()), id: \.offset) { i, pt in
                            Text("\(i + 1)")
                                .font(.caption2.bold()).foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(Circle().fill(Color.orange))
                                .position(place(pt, size))
                        }
                    }
                    Circle().stroke(Color.secondary, lineWidth: 2).frame(width: 14, height: 14)
                        .position(place(StagePoint(x: 90, y: 90), size))
                    if let target {
                        Circle().stroke(Color.blue, lineWidth: 3).frame(width: 24, height: 24)
                            .position(place(target, size))
                    }
                    Circle().fill(Color.blue).frame(width: 16, height: 16)
                        .position(place(current, size))
                        .animation(.easeInOut(duration: 0.3), value: current)
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { onTouch(snap($0.location, size), false) }
                        .onEnded { onTouch(snap($0.location, size), true) }
                )
            }
            .aspectRatio(1, contentMode: .fit)
        }

        private func grid(_ size: CGFloat) -> some View {
            Path { p in
                for a in stride(from: 0, through: 180, by: 30) {
                    let v = CGFloat(a) / 180 * size
                    p.move(to: CGPoint(x: v, y: 0))
                    p.addLine(to: CGPoint(x: v, y: size))
                    p.move(to: CGPoint(x: 0, y: v))
                    p.addLine(to: CGPoint(x: size, y: v))
                }
            }
            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        }

        private func place(_ pt: StagePoint, _ size: CGFloat) -> CGPoint {
            let fx = CGFloat(flipX ? 180 - pt.x : pt.x) / 180
            let fy = CGFloat(flipY ? pt.y : 180 - pt.y) / 180
            return CGPoint(x: fx * size, y: fy * size)
        }

        private func snap(_ loc: CGPoint, _ size: CGFloat) -> StagePoint {
            func deg(_ v: CGFloat) -> Int {
                let d = Int((v / size * 180 / 5).rounded()) * 5
                return min(180, max(0, d))
            }
            let dx = deg(loc.x)
            let dy = deg(loc.y)
            return StagePoint(x: flipX ? 180 - dx : dx, y: flipY ? dy : 180 - dy)
        }
    }
#endif
