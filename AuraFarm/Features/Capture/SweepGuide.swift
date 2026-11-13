import SwiftUI

/// The bar along the bottom of the viewfinder while a sweep runs, the way the panorama mode
/// on this phone shows a pan.
///
/// The difference is which thing moves. A panorama is the phone swung across a view; here
/// the phone is clamped over the eyepiece and the slide is pushed under it, so the bar fills
/// as the slide travels rather than as the phone turns. The arrow points the way to push,
/// and the row runs back the other way each time the slide steps down, which is how the
/// sweep walks a block of the slide rather than a single line.
struct SweepGuide: View {
    var progress: SweepProgress
    var direction: SweepDirection

    /// The cells of a row, in the order the slide passes through them. The first row runs
    /// left to right, the next comes back, so the bar always fills the way the slide is
    /// being pushed rather than always from the left.
    static func cells(inRow row: Int, framesPerRow: Int) -> [Int] {
        let cells = Array(0..<max(framesPerRow, 1))
        // `row` is counted from 1, so the first row is the left-to-right one.
        return (row - 1).isMultiple(of: 2) ? cells : cells.reversed()
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                if direction == .left { arrow }
                ForEach(Self.cells(inRow: progress.row, framesPerRow: progress.framesPerRow), id: \.self) {
                    cell in
                    Capsule()
                        .fill(cell < progress.keptInRow ? Color.green : Color.white.opacity(0.35))
                        .frame(height: 6)
                }
                if direction != .left { arrow }
            }
            .frame(maxWidth: 260)
            .animation(.easeOut(duration: 0.2), value: progress.kept)

            Text(
                "Row \(progress.row) · \(progress.kept) of \(progress.total) saved"
            )
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
        }
        .accessibilityHidden(true)
    }

    private var arrow: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18)
    }

    private var symbol: String {
        switch direction {
        case .right: "chevron.right"
        case .left: "chevron.left"
        case .down: "chevron.down"
        }
    }
}

#Preview {
    ZStack {
        Color.black
        SweepGuide(
            progress: SweepProgress(
                kept: 6, total: 12, row: 2, keptInRow: 2, framesPerRow: 4),
            direction: .left
        )
    }
}
